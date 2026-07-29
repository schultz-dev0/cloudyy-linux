"""GTK-free ccd protocol adapter for the Wi-Fi page.

Watch strategy: NetworkManager has no useful radio-state stream for this page.
``nmcli monitor`` emits no radio-state lines (verified 2026-07-07; see
``lib/ccd/watchers.py``), so the page watch polls a snapshot on an interval
and only forces ``device wifi rescan`` when the fixed ``rescan`` action runs.
"""
from __future__ import annotations

import copy
import logging
import queue
import threading
from typing import Any, Callable

from lib import wifi_core
from lib.ccd import protocol


log = logging.getLogger(__name__)
WATCH_INTERVAL_SECONDS = 4.0
SHUTDOWN_TIMEOUT_SECONDS = 2
ALLOWED_ACTIONS = set(wifi_core.ALLOWED_ACTIONS)
_STOP = object()


class SnapshotStore:
    """Provide revisioned snapshots without discarding usable stale data."""

    def __init__(
        self,
        loader: Callable[..., dict[str, Any]] = wifi_core.build_wifi_snapshot,
    ) -> None:
        self.loader = loader
        self.revision = 0
        self.last_good: dict[str, Any] | None = None
        self.last_good_revision = 0
        self.warning = ""
        self._lock = threading.Lock()

    def load(self, *, rescan: bool = False) -> dict[str, Any]:
        with self._lock:
            self.revision += 1
            revision = self.revision
        try:
            snapshot = self.loader(rescan=rescan)
        except TypeError:
            # Allow plain mocks / loaders that ignore rescan.
            try:
                snapshot = self.loader()
            except Exception as exc:
                return self._stale_from_exception(revision, exc)
        except Exception as exc:
            return self._stale_from_exception(revision, exc)

        with self._lock:
            warning = self.warning
            if revision > self.last_good_revision:
                self.last_good = copy.deepcopy(snapshot)
                self.last_good_revision = revision
        snapshot["stale"] = False
        snapshot["error"] = warning
        snapshot["revision"] = revision
        return snapshot

    def _stale_from_exception(self, revision: int, exc: Exception) -> dict[str, Any]:
        with self._lock:
            snapshot = copy.deepcopy(self.last_good)
            warning = self.warning
        if snapshot is None:
            snapshot = {
                "enabled": False,
                "active_ssid": "",
                "device": "",
                "networks": [],
            }
        snapshot["stale"] = True
        snapshot["error"] = str(exc)
        if warning:
            snapshot["error"] = f"{snapshot['error']}; {warning}"
        snapshot["revision"] = revision
        return snapshot


_snapshots = SnapshotStore()


def load_snapshot(*, rescan: bool = False) -> dict[str, Any]:
    return _snapshots.load(rescan=rescan)


def send_snapshot(*, rescan: bool = False) -> dict[str, Any]:
    snapshot = load_snapshot(rescan=rescan)
    protocol.send_event({"event": "wifi_snapshot", "snapshot": snapshot})
    return snapshot


class WifiWatcher:
    """Page-scoped periodic refresh owner (no nmcli radio stream)."""

    def __init__(
        self,
        *,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
        snapshot_loader: Callable[..., dict[str, Any]] | None = None,
        interval_seconds: float = WATCH_INTERVAL_SECONDS,
    ) -> None:
        self.event_sender = event_sender
        self.snapshot_loader = snapshot_loader or (lambda **kwargs: load_snapshot(**kwargs))
        self.interval_seconds = interval_seconds
        self.requested = False
        self.thread: threading.Thread | None = None
        self.warning = ""
        self._lock = threading.RLock()
        self._emit_lock = threading.Lock()
        self._wake = threading.Event()
        self._epoch = 0

    def start(self) -> None:
        with self._lock:
            if self.requested:
                return
            self.requested = True
            self.warning = ""
            _snapshots.warning = ""
            self._epoch += 1
            self._wake.clear()
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()

    def _run(self) -> None:
        while True:
            with self._lock:
                if not self.requested:
                    return
                epoch = self._epoch
            self._emit_snapshot(epoch)
            woken = self._wake.wait(self.interval_seconds)
            self._wake.clear()
            if woken:
                with self._lock:
                    if not self.requested:
                        return

    def _emit_snapshot(self, epoch: int) -> None:
        with self._emit_lock:
            with self._lock:
                if not self.requested or epoch != self._epoch:
                    return
            snapshot = self.snapshot_loader(rescan=False)
            with self._lock:
                if not self.requested or epoch != self._epoch:
                    return
            self.event_sender({"event": "wifi_snapshot", "snapshot": snapshot})

    def stop(self) -> bool:
        with self._lock:
            self.requested = False
            self._epoch += 1
        self._wake.set()
        emitter_stopped = self._emit_lock.acquire(timeout=SHUTDOWN_TIMEOUT_SECONDS)
        if not emitter_stopped:
            log.warning("Wi-Fi watcher did not stop before emitter timeout")
        else:
            self._emit_lock.release()
        thread = self.thread
        thread_stopped = True
        if thread is threading.current_thread():
            thread_stopped = False
        elif thread is not None:
            thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)
            thread_stopped = not thread.is_alive()
            if not thread_stopped:
                log.warning("Wi-Fi watcher thread did not stop before timeout")
        return bool(emitter_stopped and thread_stopped)


class WifiActionWorker:
    """Execute frontend-validated Wi-Fi actions in submission order."""

    def __init__(
        self,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
        executor: Callable[[str, str, Any], tuple[bool, str]] = wifi_core.execute_wifi_action,
        snapshot_loader: Callable[..., dict[str, Any]] = load_snapshot,
        *,
        start_thread: bool = True,
    ) -> None:
        self.queue: queue.Queue[dict[str, Any] | object] = queue.Queue()
        self.event_sender = event_sender
        self.executor = executor
        self.snapshot_loader = snapshot_loader
        self.thread: threading.Thread | None = None
        if start_thread:
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()

    def submit(self, request: dict[str, Any]) -> None:
        self.queue.put(dict(request))

    def _run(self) -> None:
        while True:
            request = self.queue.get()
            if request is _STOP:
                return
            if not isinstance(request, dict):
                log.warning("Ignoring malformed queued wifi action")
                continue
            try:
                request = dict(request)
                request["generation"] = _coerce_generation(request.get("generation", 0))
                self.process(request)
            except Exception as exc:
                # Never include action params (may hold password/identity).
                log.warning("Ignoring malformed queued wifi action: %s", exc)

    def process(self, request: dict[str, Any]) -> None:
        action = str(request.get("action", ""))
        target = str(request.get("target", ""))
        try:
            ok, message = self.executor(action, target, request.get("value"))
        except Exception as exc:
            # Log action name only — value may contain secrets.
            log.warning("wifi action %s failed: %s", action, exc)
            ok, message = False, str(exc)
        try:
            snapshot = self.snapshot_loader(rescan=False)
        except TypeError:
            snapshot = self.snapshot_loader()
        self.event_sender({
            "event": "wifi_action_done",
            "action_id": str(request["action_id"]),
            "target": target,
            "generation": int(request.get("generation", 0)),
            "ok": ok,
            "message": message,
            "stale_target": False,
        })
        self.event_sender({"event": "wifi_snapshot", "snapshot": snapshot})

    def shutdown(self) -> None:
        if self.thread is None:
            return
        self.queue.put(_STOP)
        self.thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)


_watcher: WifiWatcher | None = None
_action_worker: WifiActionWorker | None = None


def _get_watcher() -> WifiWatcher:
    global _watcher
    if _watcher is None:
        _watcher = WifiWatcher()
    return _watcher


def _get_action_worker() -> WifiActionWorker:
    global _action_worker
    if _action_worker is None:
        _action_worker = WifiActionWorker()
    return _action_worker


def _require_name(value: Any, what: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{what} is required")
    return value


def _coerce_generation(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, bool):
        raise ValueError("generation must be a non-negative integer")
    try:
        generation = int(value)
    except (TypeError, ValueError, OverflowError) as exc:
        raise ValueError("generation must be a non-negative integer") from exc
    if generation < 0 or (isinstance(value, float) and not value.is_integer()):
        raise ValueError("generation must be a non-negative integer")
    return generation


def _validate_action_params(action: str, target: str, value: Any) -> None:
    if action == "set_radio":
        if not isinstance(value, bool):
            raise ValueError("radio value must be a boolean")
        return
    if action == "rescan":
        return
    if action == "disconnect":
        return
    if action in ("connect", "forget"):
        _require_name(target, "ssid")
        if action == "connect" and value is not None and value != "" and not isinstance(value, str):
            raise ValueError("password must be a string")
        return
    if action == "connect_enterprise":
        _require_name(target, "ssid")
        wifi_core._enterprise_credentials(value)
        return
    raise ValueError(f"unknown wifi action: {action}")


def run_wifi_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown wifi action: {action}")
    target = params.get("target", "")
    if target is None:
        target = ""
    if not isinstance(target, str):
        raise ValueError("target must be a string")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    _validate_action_params(action, target, params.get("value"))
    request = {
        "action": action,
        "target": target,
        "value": params.get("value"),
        "action_id": action_id,
        "generation": generation,
    }
    _get_action_worker().submit(request)
    return {"queued": True, "action_id": action_id, "generation": generation}


def get_wifi_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def start_wifi_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_wifi_watch(_params: dict[str, Any]) -> dict[str, Any]:
    stopped = _watcher is None or _watcher.stop()
    return {
        "ok": stopped,
        "message": "" if stopped else "Wi-Fi watcher is still stopping",
    }


def shutdown() -> None:
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_wifi_snapshot", get_wifi_snapshot)
protocol.register("start_wifi_watch", start_wifi_watch)
protocol.register("stop_wifi_watch", stop_wifi_watch)
protocol.register("run_wifi_action", run_wifi_action)
