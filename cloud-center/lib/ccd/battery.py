"""GTK-free ccd protocol adapter for the Battery page."""
from __future__ import annotations

import copy
import logging
import queue
import threading
import time
from typing import Any, Callable

from lib import battery_core
from lib.ccd import protocol

log = logging.getLogger(__name__)
SHUTDOWN_TIMEOUT_SECONDS = 2
WATCH_INTERVAL_SECONDS = 30.0
ALLOWED_ACTIONS = battery_core.ALLOWED_ACTIONS
_STOP = object()


class SnapshotStore:
    def __init__(self, loader: Callable[[], dict[str, Any]] | None = None) -> None:
        self.loader = loader or battery_core.build_battery_snapshot
        self.revision = 0
        self.last_good: dict[str, Any] | None = None
        self.last_good_revision = 0
        self._lock = threading.Lock()

    def load(self) -> dict[str, Any]:
        with self._lock:
            self.revision += 1
            revision = self.revision
        try:
            snapshot = self.loader()
        except Exception as exc:
            with self._lock:
                snapshot = copy.deepcopy(self.last_good)
            if snapshot is None:
                snapshot = {
                    "present": False,
                    "capabilities": {"threshold": False, "asus_mode": False},
                    "info": None,
                    "display": {},
                    "asus_modes": list(battery_core.ASUS_MODES),
                    "asus_mode_descriptions": list(battery_core.ASUS_MODE_DESCS),
                }
            snapshot["stale"] = True
            snapshot["error"] = str(exc)
            snapshot["revision"] = revision
            return snapshot

        snapshot = dict(snapshot)
        with self._lock:
            if revision > self.last_good_revision:
                self.last_good = copy.deepcopy(snapshot)
                self.last_good_revision = revision
        snapshot["stale"] = False
        snapshot["error"] = snapshot.get("error", "")
        snapshot["revision"] = revision
        return snapshot


class BatteryWatcher:
    def __init__(
        self,
        interval: float = WATCH_INTERVAL_SECONDS,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.interval = interval
        self.emitter = emitter or (
            lambda snapshot: protocol.send_event(
                {"event": "battery_snapshot", "snapshot": snapshot}
            )
        )
        self.loader = loader or load_snapshot
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._lock = threading.Lock()

    def start(self) -> None:
        with self._lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop.clear()
            self._thread = threading.Thread(
                target=self._run, name="battery-watch", daemon=True,
            )
            self._thread.start()

    def stop(self) -> bool:
        self._stop.set()
        thread = self._thread
        if thread is None:
            return True
        thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)
        return not thread.is_alive()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                self.emitter(self.loader())
            except Exception as exc:
                log.debug("battery watch emit failed: %s", exc)
            self._stop.wait(self.interval)


class ActionWorker:
    def __init__(
        self,
        runner: Callable[..., dict[str, Any]] | None = None,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        snapshot_loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.runner = runner or battery_core.run_battery_action
        self.emitter = emitter or protocol.send_event
        self.snapshot_loader = snapshot_loader or load_snapshot
        self._queue: queue.Queue[Any] = queue.Queue()
        self._thread = threading.Thread(
            target=self._run, name="battery-actions", daemon=True,
        )
        self._thread.start()

    def submit(self, request: dict[str, Any]) -> None:
        self._queue.put(request)

    def shutdown(self) -> None:
        self._queue.put(_STOP)
        self._thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)

    def _run(self) -> None:
        while True:
            item = self._queue.get()
            if item is _STOP:
                return
            action_id = str(item.get("action_id", ""))
            target = str(item.get("target", ""))
            generation = int(item.get("generation", 0))
            ok = False
            message = ""
            try:
                result = self.runner(item["action"], item.get("value"))
                ok = bool(result.get("ok"))
                message = str(result.get("message", ""))
            except Exception as exc:
                ok = False
                message = str(exc)
            self.emitter({
                "event": "battery_action_done",
                "action_id": action_id,
                "target": target,
                "generation": generation,
                "ok": ok,
                "stale_target": False,
                "message": message,
            })
            try:
                self.emitter({
                    "event": "battery_snapshot",
                    "snapshot": self.snapshot_loader(),
                })
            except Exception as exc:
                log.debug("battery post-action snapshot failed: %s", exc)


_snapshots = SnapshotStore()
_watcher: BatteryWatcher | None = None
_action_worker: ActionWorker | None = None
_worker_lock = threading.Lock()


def load_snapshot() -> dict[str, Any]:
    return _snapshots.load()


def _get_watcher() -> BatteryWatcher:
    global _watcher
    with _worker_lock:
        if _watcher is None:
            _watcher = BatteryWatcher()
        return _watcher


def _get_action_worker() -> ActionWorker:
    global _action_worker
    with _worker_lock:
        if _action_worker is None:
            _action_worker = ActionWorker()
        return _action_worker


def _coerce_generation(value: Any) -> int:
    try:
        generation = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("generation must be a non-negative integer") from exc
    if generation < 0:
        raise ValueError("generation must be a non-negative integer")
    return generation


def run_battery_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown battery action: {action}")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    value = params.get("value")
    if action == "set_threshold":
        try:
            value = int(value)
        except (TypeError, ValueError) as exc:
            raise ValueError("threshold must be an integer") from exc
    elif action == "set_charge_mode":
        try:
            value = int(value)
        except (TypeError, ValueError) as exc:
            raise ValueError("charge mode must be an integer") from exc
    target = str(params.get("target") or action)
    _get_action_worker().submit({
        "action": action,
        "target": target,
        "value": value,
        "action_id": action_id,
        "generation": generation,
    })
    return {"queued": True, "action_id": action_id, "generation": generation}


def get_battery_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def start_battery_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_battery_watch(_params: dict[str, Any]) -> dict[str, Any]:
    stopped = _watcher is None or _watcher.stop()
    return {
        "ok": stopped,
        "message": "" if stopped else "Battery watcher is still stopping",
    }


def shutdown() -> None:
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_battery_snapshot", get_battery_snapshot)
protocol.register("start_battery_watch", start_battery_watch)
protocol.register("stop_battery_watch", stop_battery_watch)
protocol.register("run_battery_action", run_battery_action)
