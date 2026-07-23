"""GTK-free ccd protocol adapter for the Bluetooth page."""
from __future__ import annotations

import copy
import logging
import queue
import subprocess
import threading
import time
from typing import Any, Callable

from lib import bluetooth_core
from lib.ccd import protocol


log = logging.getLogger(__name__)
SHUTDOWN_TIMEOUT_SECONDS = 2
WATCH_INTERVAL_SECONDS = 2.0
DEFAULT_SCAN_SECONDS = 8.0
ALLOWED_ACTIONS = bluetooth_core.ALLOWED_ACTIONS
_STOP = object()


class SnapshotStore:
    """Provide revisioned snapshots without discarding usable stale data."""

    def __init__(
        self,
        loader: Callable[..., dict[str, Any]] | None = None,
        scanning_probe: Callable[[], bool] | None = None,
    ) -> None:
        self.loader = loader or (
            lambda **kwargs: bluetooth_core.build_bluetooth_snapshot(**kwargs)
        )
        self.scanning_probe = scanning_probe or (lambda: False)
        self.revision = 0
        self.last_good: dict[str, Any] | None = None
        self.last_good_revision = 0
        self.warning = ""
        self._lock = threading.Lock()

    def load(self, *, force: bool = False) -> dict[str, Any]:
        with self._lock:
            self.revision += 1
            revision = self.revision
        try:
            snapshot = self.loader(
                scanning=self.scanning_probe(), force=force,
            )
        except TypeError:
            # Test loaders may ignore keyword args.
            try:
                snapshot = self.loader()  # type: ignore[call-arg]
            except Exception as exc:
                return self._stale_from_error(revision, exc)
        except Exception as exc:
            return self._stale_from_error(revision, exc)
        else:
            with self._lock:
                warning = self.warning
                if revision > self.last_good_revision:
                    self.last_good = copy.deepcopy(snapshot)
                    self.last_good_revision = revision
            snapshot = dict(snapshot)
            snapshot["stale"] = False
            snapshot["error"] = warning or snapshot.get("error", "")
            snapshot["revision"] = revision
            snapshot["scanning"] = bool(
                snapshot.get("scanning", False) or self.scanning_probe()
            )
            return snapshot

    def _stale_from_error(self, revision: int, exc: Exception) -> dict[str, Any]:
        with self._lock:
            snapshot = copy.deepcopy(self.last_good)
            warning = self.warning
        if snapshot is None:
            snapshot = {
                "powered": False,
                "scanning": False,
                "devices": [],
            }
        snapshot["stale"] = True
        snapshot["error"] = str(exc)
        if warning:
            snapshot["error"] = f"{snapshot['error']}; {warning}"
        snapshot["revision"] = revision
        snapshot["scanning"] = self.scanning_probe()
        return snapshot


_snapshots = SnapshotStore(scanning_probe=lambda: _scan_is_active())


def load_snapshot(*, force: bool = False) -> dict[str, Any]:
    return _snapshots.load(force=force)


def send_snapshot(*, force: bool = False) -> dict[str, Any]:
    snapshot = load_snapshot(force=force)
    protocol.send_event({"event": "bluetooth_snapshot", "snapshot": snapshot})
    return snapshot


class ScanSession:
    """Own one interactive bluetoothctl scan process end-to-end."""

    def __init__(
        self,
        *,
        popen: Any = subprocess.Popen,
        sleeper: Callable[[float], None] = time.sleep,
        duration: float = DEFAULT_SCAN_SECONDS,
        on_finished: Callable[[], None] | None = None,
    ) -> None:
        self.popen = popen
        self.sleeper = sleeper
        self.duration = duration
        self.on_finished = on_finished
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self.active = False

    def request_stop(self) -> None:
        self._stop.set()

    def start(self, duration: float | None = None) -> tuple[bool, str]:
        with self._lock:
            if self.active:
                return False, "Scan already in progress"
            self._stop.clear()
            if duration is not None:
                self.duration = float(duration)
            self.active = True
            self._thread = threading.Thread(target=self._thread_main, daemon=True)
            self._thread.start()
        return True, ""

    def _thread_main(self) -> None:
        try:
            self.run()
        finally:
            with self._lock:
                self.active = False
            if self.on_finished is not None:
                try:
                    self.on_finished()
                except Exception as exc:
                    log.debug("bluetooth scan on_finished failed: %s", exc)

    def run(self) -> tuple[bool, str]:
        return bluetooth_core.run_scan_session(
            self.duration,
            should_stop=self._stop.is_set,
            popen=self.popen,
            sleeper=self.sleeper,
        )

    def stop(self) -> bool:
        self.request_stop()
        thread = self._thread
        if thread is None:
            with self._lock:
                self.active = False
            return True
        if thread is threading.current_thread():
            return False
        thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS + self.duration)
        alive = thread.is_alive()
        if not alive:
            with self._lock:
                self.active = False
        return not alive


class BluetoothWatcher:
    """Page-scoped periodic snapshot poller."""

    def __init__(
        self,
        *,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
        snapshot_loader: Callable[[], dict[str, Any]] | None = None,
        interval: float = WATCH_INTERVAL_SECONDS,
    ) -> None:
        self.event_sender = event_sender
        self.snapshot_loader = snapshot_loader or (lambda: load_snapshot())
        self.interval = interval
        self.requested = False
        self.thread: threading.Thread | None = None
        self.warning = ""
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._emit_lock = threading.Lock()
        self._epoch = 0

    def start(self) -> None:
        with self._lock:
            if self.requested:
                return
            self.requested = True
            self.warning = ""
            _snapshots.warning = ""
            self._stop.clear()
            self._epoch += 1
            self.thread = threading.Thread(target=self._run, daemon=True)
            self.thread.start()

    def _run(self) -> None:
        while not self._stop.is_set():
            with self._lock:
                if not self.requested:
                    break
                epoch = self._epoch
            self._emit(epoch)
            if self._stop.wait(self.interval):
                break

    def _emit(self, epoch: int) -> None:
        with self._emit_lock:
            with self._lock:
                if not self.requested or epoch != self._epoch:
                    return
            snapshot = self.snapshot_loader()
            with self._lock:
                if not self.requested or epoch != self._epoch:
                    return
            self.event_sender({"event": "bluetooth_snapshot", "snapshot": snapshot})

    def stop(self) -> bool:
        with self._lock:
            self.requested = False
            self._epoch += 1
        self._stop.set()
        emitter_stopped = self._emit_lock.acquire(timeout=SHUTDOWN_TIMEOUT_SECONDS)
        if not emitter_stopped:
            log.warning("Bluetooth watcher did not stop before emitter timeout")
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
                log.warning("Bluetooth watcher thread did not stop before timeout")
        return bool(emitter_stopped and thread_stopped)


def target_present(action: str, target: str, snapshot: dict[str, Any]) -> bool:
    if action in ("set_power", "start_scan", "stop_scan"):
        return True
    return any(
        str(item.get("address")) == str(target)
        for item in snapshot.get("devices", [])
    )


class BluetoothActionWorker:
    """Execute frontend-validated bluetooth actions in submission order."""

    def __init__(
        self,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
        executor: Callable[[str, str, Any], tuple[bool, str]] | None = None,
        snapshot_loader: Callable[[], dict[str, Any]] | None = None,
        *,
        start_thread: bool = True,
    ) -> None:
        self.queue: queue.Queue[dict[str, Any] | object] = queue.Queue()
        self.event_sender = event_sender
        self.executor = executor or bluetooth_core.execute_bluetooth_action
        self.snapshot_loader = snapshot_loader or (lambda: load_snapshot(force=True))
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
                log.warning("Ignoring malformed queued bluetooth action")
                continue
            try:
                request = dict(request)
                request["generation"] = _coerce_generation(request.get("generation", 0))
                self.process(request)
            except Exception as exc:
                log.warning("Ignoring malformed queued bluetooth action: %s", exc)

    def process(self, request: dict[str, Any]) -> None:
        action = str(request["action"])
        try:
            if action == "start_scan":
                ok, message = self._start_scan(request.get("value"))
            elif action == "stop_scan":
                ok, message = self._stop_scan()
            else:
                ok, message = self.executor(
                    action, str(request["target"]), request.get("value"),
                )
        except Exception as exc:
            ok, message = False, str(exc)
        snapshot = self.snapshot_loader()
        stale_target = not ok and not target_present(
            action, str(request["target"]), snapshot,
        )
        self.event_sender({
            "event": "bluetooth_action_done",
            "action_id": str(request["action_id"]),
            "target": str(request["target"]),
            "generation": int(request.get("generation", 0)),
            "ok": ok,
            "message": "" if stale_target else message,
            "stale_target": stale_target,
        })
        self.event_sender({"event": "bluetooth_snapshot", "snapshot": snapshot})

    def _start_scan(self, value: Any) -> tuple[bool, str]:
        duration = DEFAULT_SCAN_SECONDS
        if value is not None:
            try:
                duration = float(value)
            except (TypeError, ValueError) as exc:
                raise ValueError("scan duration must be a number") from exc
        session = _get_scan_session()
        ok, message = session.start(duration)
        if ok:
            # Emit an intermediate scanning snapshot before the session finishes.
            self.event_sender({
                "event": "bluetooth_snapshot",
                "snapshot": load_snapshot(force=False),
            })
            # Wait for the scan thread so connect/remove stay ordered after scan.
            thread = session._thread
            if thread is not None and thread is not threading.current_thread():
                thread.join(timeout=duration + SHUTDOWN_TIMEOUT_SECONDS + 2)
            ok = True
            message = ""
        return ok, message

    def _stop_scan(self) -> tuple[bool, str]:
        session = _get_scan_session()
        stopped = session.stop()
        return stopped, "" if stopped else "Scan is still stopping"

    def shutdown(self) -> None:
        if self.thread is None:
            return
        self.queue.put(_STOP)
        self.thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)


_watcher: BluetoothWatcher | None = None
_action_worker: BluetoothActionWorker | None = None
_scan_session: ScanSession | None = None


def _scan_is_active() -> bool:
    return _scan_session is not None and _scan_session.active


def _on_scan_finished() -> None:
    try:
        send_snapshot(force=True)
    except Exception as exc:
        log.debug("bluetooth post-scan snapshot failed: %s", exc)


def _get_watcher() -> BluetoothWatcher:
    global _watcher
    if _watcher is None:
        _watcher = BluetoothWatcher()
    return _watcher


def _get_action_worker() -> BluetoothActionWorker:
    global _action_worker
    if _action_worker is None:
        _action_worker = BluetoothActionWorker()
    return _action_worker


def _get_scan_session() -> ScanSession:
    global _scan_session
    if _scan_session is None or (
        not _scan_session.active and _scan_session._thread is not None
        and not _scan_session._thread.is_alive()
    ):
        _scan_session = ScanSession(on_finished=_on_scan_finished)
    return _scan_session


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


def run_bluetooth_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown bluetooth action: {action}")
    raw_target = params.get("target", "adapter")
    if action in ("set_power", "start_scan", "stop_scan"):
        target = str(raw_target or "adapter")
    else:
        target = _require_name(raw_target, "target")
        if not bluetooth_core.is_mac_address(target):
            raise ValueError(f"invalid bluetooth address: {target}")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    if action == "set_power" and not isinstance(params.get("value"), bool):
        raise ValueError("power value must be a boolean")
    if action == "trust" and not isinstance(params.get("value"), bool):
        raise ValueError("trust value must be a boolean")
    snapshot = load_snapshot()
    if action not in ("set_power", "start_scan", "stop_scan"):
        if not target_present(action, target, snapshot):
            raise ValueError(f"unknown device: {target}")
    if action == "start_scan" and not snapshot.get("powered", False):
        raise ValueError("Bluetooth is powered off")
    request = dict(params)
    request.update({
        "action": action,
        "target": target,
        "action_id": action_id,
        "generation": generation,
    })
    _get_action_worker().submit(request)
    return {"queued": True, "action_id": action_id, "generation": generation}


def get_bluetooth_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def start_bluetooth_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_bluetooth_watch(_params: dict[str, Any]) -> dict[str, Any]:
    session_stopped = _scan_session is None or _scan_session.stop()
    watcher_stopped = _watcher is None or _watcher.stop()
    stopped = bool(session_stopped and watcher_stopped)
    return {
        "ok": stopped,
        "message": "" if stopped else "Bluetooth watcher is still stopping",
    }


def shutdown() -> None:
    if _scan_session is not None:
        _scan_session.stop()
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_bluetooth_snapshot", get_bluetooth_snapshot)
protocol.register("start_bluetooth_watch", start_bluetooth_watch)
protocol.register("stop_bluetooth_watch", stop_bluetooth_watch)
protocol.register("run_bluetooth_action", run_bluetooth_action)
