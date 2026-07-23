"""GTK-free ccd protocol adapter for the Region & Time page."""
from __future__ import annotations

import copy
import logging
import queue
import threading
from typing import Any, Callable

from lib import region_time_core
from lib.ccd import protocol

log = logging.getLogger(__name__)
SHUTDOWN_TIMEOUT_SECONDS = 2
WATCH_INTERVAL_SECONDS = 5.0
LOCATION_REFRESH_EVERY = 6  # every ~30s at 5s watch interval
ALLOWED_ACTIONS = region_time_core.ALLOWED_ACTIONS
_STOP = object()


class SnapshotStore:
    def __init__(
        self,
        loader: Callable[..., dict[str, Any]] | None = None,
    ) -> None:
        self.loader = loader or region_time_core.build_region_snapshot
        self.revision = 0
        self.last_good: dict[str, Any] | None = None
        self.last_good_revision = 0
        self._lock = threading.Lock()
        self._ticks = 0

    def load(self, *, include_location: bool = True) -> dict[str, Any]:
        with self._lock:
            self.revision += 1
            revision = self.revision
        try:
            snapshot = self.loader(include_location=include_location)
        except Exception as exc:
            with self._lock:
                snapshot = copy.deepcopy(self.last_good)
            if snapshot is None:
                snapshot = {
                    "polkit_ready": False,
                    "timezone": "",
                    "ntp_enabled": False,
                    "manual_location": False,
                    "location": None,
                    "clock": {},
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

    def load_for_watch(self) -> dict[str, Any]:
        with self._lock:
            self._ticks += 1
            include_location = (self._ticks % LOCATION_REFRESH_EVERY) == 1
        return self.load(include_location=include_location)


class RegionWatcher:
    def __init__(
        self,
        interval: float = WATCH_INTERVAL_SECONDS,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.interval = interval
        self.emitter = emitter or (
            lambda snapshot: protocol.send_event(
                {"event": "region_snapshot", "snapshot": snapshot}
            )
        )
        self.loader = loader or load_watch_snapshot
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()
        self._lock = threading.Lock()

    def start(self) -> None:
        with self._lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop.clear()
            self._thread = threading.Thread(
                target=self._run, name="region-watch", daemon=True,
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
                log.debug("region watch emit failed: %s", exc)
            self._stop.wait(self.interval)


class ActionWorker:
    def __init__(
        self,
        runner: Callable[..., dict[str, Any]] | None = None,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        snapshot_loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.runner = runner or region_time_core.run_region_action
        self.emitter = emitter or protocol.send_event
        self.snapshot_loader = snapshot_loader or load_snapshot
        self._queue: queue.Queue[Any] = queue.Queue()
        self._thread = threading.Thread(
            target=self._run, name="region-actions", daemon=True,
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
                "event": "region_action_done",
                "action_id": action_id,
                "target": target,
                "generation": generation,
                "ok": ok,
                "stale_target": False,
                "message": message,
            })
            try:
                self.emitter({
                    "event": "region_snapshot",
                    "snapshot": self.snapshot_loader(),
                })
            except Exception as exc:
                log.debug("region post-action snapshot failed: %s", exc)


_snapshots = SnapshotStore()
_watcher: RegionWatcher | None = None
_action_worker: ActionWorker | None = None
_worker_lock = threading.Lock()
_timezones_cache: dict[str, Any] | None = None
_timezones_lock = threading.Lock()


def load_snapshot() -> dict[str, Any]:
    return _snapshots.load(include_location=True)


def load_watch_snapshot() -> dict[str, Any]:
    return _snapshots.load_for_watch()


def _get_watcher() -> RegionWatcher:
    global _watcher
    with _worker_lock:
        if _watcher is None:
            _watcher = RegionWatcher()
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


def run_region_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown region action: {action}")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    value = params.get("value")
    if action == "set_ntp":
        if not isinstance(value, bool):
            raise ValueError("ntp value must be a boolean")
    elif action == "set_manual_mode":
        if not isinstance(value, bool):
            raise ValueError("manual mode must be a boolean")
    elif action == "set_timezone":
        if not isinstance(value, str) or not value.strip():
            raise ValueError("timezone must be a non-empty string")
        value = value.strip()
    elif action == "set_time":
        if not isinstance(value, dict):
            raise ValueError("time value must be an object")
    elif action == "apply_location":
        if not isinstance(value, dict):
            raise ValueError("location value must be an object")
    target = str(params.get("target") or action)
    _get_action_worker().submit({
        "action": action,
        "target": target,
        "value": value,
        "action_id": action_id,
        "generation": generation,
    })
    return {"queued": True, "action_id": action_id, "generation": generation}


def get_region_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def get_region_timezones(_params: dict[str, Any]) -> dict[str, Any]:
    global _timezones_cache
    with _timezones_lock:
        if _timezones_cache is None:
            _timezones_cache = region_time_core.list_timezones_payload()
        return copy.deepcopy(_timezones_cache)


def start_region_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_region_watch(_params: dict[str, Any]) -> dict[str, Any]:
    stopped = _watcher is None or _watcher.stop()
    return {
        "ok": stopped,
        "message": "" if stopped else "Region watcher is still stopping",
    }


def shutdown() -> None:
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_region_snapshot", get_region_snapshot)
protocol.register("get_region_timezones", get_region_timezones)
protocol.register("start_region_watch", start_region_watch)
protocol.register("stop_region_watch", stop_region_watch)
protocol.register("run_region_action", run_region_action)
