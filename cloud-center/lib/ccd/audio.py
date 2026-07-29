"""GTK-free ccd protocol adapter for the Audio page."""
from __future__ import annotations

import copy
import logging
import queue
import subprocess
import threading
from typing import Any, Callable

from lib import audio_core, audio_service_control as service_control
from lib.ccd import protocol


log = logging.getLogger(__name__)
WATCH_DEBOUNCE_SECONDS = 0.15
SHUTDOWN_TIMEOUT_SECONDS = 2
ALLOWED_ACTIONS = {
    "set_sink_volume", "set_source_volume", "set_stream_volume",
    "set_sink_mute", "set_source_mute", "set_stream_mute",
    "set_default_sink", "set_default_source", "move_stream",
    "set_sink_port", "set_source_port", "set_card_profile",
}
_STOP = object()


class SnapshotStore:
    """Provide revisioned snapshots without discarding usable stale data."""

    def __init__(
        self,
        loader: Callable[[dict[str, Any]], dict[str, Any]] = audio_core.build_audio_snapshot,
        service_loader: Callable[[], dict[str, Any]] = service_control.service_status,
    ) -> None:
        self.loader = loader
        self.service_loader = service_loader
        self.revision = 0
        self.last_good: dict[str, Any] | None = None
        self.last_good_revision = 0
        self.warning = ""
        self._lock = threading.Lock()

    def load(self) -> dict[str, Any]:
        with self._lock:
            self.revision += 1
            revision = self.revision
        service: dict[str, Any] = {}
        try:
            service = self.service_loader()
            snapshot = self.loader(service)
        except Exception as exc:
            try:
                default_automation = audio_core.load_auto_switch_config()
            except Exception:
                default_automation = {}
            with self._lock:
                snapshot = copy.deepcopy(self.last_good)
                warning = self.warning
            if snapshot is None:
                snapshot = {
                    "sinks": [], "sources": [], "streams": [], "cards": [],
                    "automation": default_automation, "service": service,
                }
            snapshot["stale"] = True
            snapshot["error"] = str(exc)
            if warning:
                snapshot["error"] = f"{snapshot['error']}; {warning}"
        else:
            with self._lock:
                warning = self.warning
                if revision > self.last_good_revision:
                    self.last_good = copy.deepcopy(snapshot)
                    self.last_good_revision = revision
            snapshot["stale"] = False
            snapshot["error"] = warning
        snapshot["revision"] = revision
        return snapshot


_snapshots = SnapshotStore()


def load_snapshot() -> dict[str, Any]:
    return _snapshots.load()


def send_snapshot() -> dict[str, Any]:
    snapshot = load_snapshot()
    protocol.send_event({"event": "audio_snapshot", "snapshot": snapshot})
    return snapshot


class AudioWatcher:
    """Page-scoped, debounced owner of a single ``pactl subscribe`` child."""

    def __init__(
        self,
        *,
        popen: Any = subprocess.Popen,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
    ) -> None:
        self.popen = popen
        self.event_sender = event_sender
        self.requested = False
        self.process: Any = None
        self.thread: threading.Thread | None = None
        self.timer: threading.Timer | None = None
        self.warning = ""
        self._restart_count = 0
        self._lock = threading.RLock()
        self._emit_lock = threading.Lock()
        self._epoch = 0

    def start(self) -> None:
        with self._lock:
            if self.requested:
                return
            self.requested = True
            self.warning = ""
            _snapshots.warning = ""
            self._restart_count = 0
            self._epoch += 1
            self._start_thread()

    def _start_thread(self) -> None:
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self) -> None:
        child: Any = None
        try:
            child = self.popen(
                ["pactl", "subscribe"], stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True,
            )
            with self._lock:
                if not self.requested:
                    cleanup_child = child
                else:
                    cleanup_child = None
                    self.process = child
            if cleanup_child is not None:
                self._terminate_child(cleanup_child)
                return
            if child.stdout is not None:
                for line in child.stdout:
                    with self._lock:
                        if not self.requested:
                            break
                    self.handle_event(line)
        except (OSError, subprocess.SubprocessError) as exc:
            log.warning("Audio subscription failed: %s", exc)
        finally:
            with self._lock:
                if self.process is child:
                    self.process = None
                unexpected = self.requested
            if unexpected:
                self._unexpected_exit()

    def handle_event(self, line: str) -> None:
        lowered = line.lower()
        if not any(f"on {kind}" in lowered for kind in ("sink", "source", "sink-input", "card")):
            return
        with self._lock:
            if not self.requested:
                return
            if self.timer is not None:
                self.timer.cancel()
            epoch = self._epoch
            self.timer = threading.Timer(
                WATCH_DEBOUNCE_SECONDS, self._send_debounced_snapshot, args=(epoch,),
            )
            self.timer.daemon = True
            self.timer.start()

    def _send_debounced_snapshot(self, epoch: int | None = None) -> None:
        """Emit one snapshot unless stop invalidated this debounce generation."""
        with self._lock:
            active_epoch = self._epoch if epoch is None else epoch
        with self._emit_lock:
            with self._lock:
                if active_epoch == self._epoch:
                    self.timer = None
                if not self.requested or active_epoch != self._epoch:
                    return
            snapshot = load_snapshot()
            with self._lock:
                if not self.requested or active_epoch != self._epoch:
                    return
            self.event_sender({"event": "audio_snapshot", "snapshot": snapshot})

    def _unexpected_exit(self) -> None:
        with self._lock:
            if not self.requested:
                return
            if self._restart_count < 1:
                self._restart_count += 1
                self._start_thread()
                return
            self.warning = "Audio live updates stopped; use Refresh to retry."
            _snapshots.warning = self.warning

    @staticmethod
    def _terminate_child(child: Any) -> bool:
        if child is None:
            return True
        try:
            if child.poll() is not None:
                return True
            child.terminate()
            child.wait(timeout=SHUTDOWN_TIMEOUT_SECONDS)
            return True
        except subprocess.TimeoutExpired:
            try:
                child.kill()
                child.wait(timeout=SHUTDOWN_TIMEOUT_SECONDS)
                return True
            except subprocess.TimeoutExpired:
                log.warning("Timed out reaping pactl subscribe")
                return False
        except ProcessLookupError:
            return True
        except OSError as exc:
            log.warning("Could not reap pactl subscribe: %s", exc)
            return False

    def stop(self) -> bool:
        with self._lock:
            self.requested = False
            self._epoch += 1
            timer, self.timer = self.timer, None
            child, self.process = self.process, None
        if timer is not None:
            timer.cancel()
        child_stopped = self._terminate_child(child)
        emitter_stopped = self._emit_lock.acquire(timeout=SHUTDOWN_TIMEOUT_SECONDS)
        if not emitter_stopped:
            log.warning("Audio watcher did not stop before emitter timeout")
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
                log.warning("Audio watcher thread did not stop before timeout")
        return bool(child_stopped and emitter_stopped and thread_stopped)


def target_present(action: str, target: str, snapshot: dict[str, Any]) -> bool:
    if action.startswith("set_sink_") or action == "set_default_sink":
        return any(item.get("name") == target for item in snapshot.get("sinks", []))
    if action.startswith("set_source_") or action == "set_default_source":
        return any(item.get("name") == target for item in snapshot.get("sources", []))
    if action.startswith("set_stream_") or action == "move_stream":
        return any(str(item.get("index")) == target for item in snapshot.get("streams", []))
    if action == "set_card_profile":
        return any(item.get("name") == target for item in snapshot.get("cards", []))
    return False


class AudioActionWorker:
    """Execute frontend-validated audio actions in exactly submission order."""

    def __init__(
        self,
        event_sender: Callable[[dict[str, Any]], None] = protocol.send_event,
        executor: Callable[[str, str, Any], tuple[bool, str]] = audio_core.execute_audio_action,
        snapshot_loader: Callable[[], dict[str, Any]] = load_snapshot,
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
                log.warning("Ignoring malformed queued audio action")
                continue
            try:
                request = dict(request)
                request["generation"] = _coerce_generation(request.get("generation", 0))
                self.process(request)
            except Exception as exc:
                log.warning("Ignoring malformed queued audio action: %s", exc)

    def process(self, request: dict[str, Any]) -> None:
        try:
            ok, message = self.executor(
                request["action"], str(request["target"]), request.get("value"),
            )
        except Exception as exc:
            ok, message = False, str(exc)
        snapshot = self.snapshot_loader()
        stale_target = not ok and not target_present(
            request["action"], str(request["target"]), snapshot,
        )
        self.event_sender({
            "event": "audio_action_done", "action_id": str(request["action_id"]),
            "target": str(request["target"]),
            "generation": int(request.get("generation", 0)), "ok": ok,
            "message": "" if stale_target else message, "stale_target": stale_target,
        })
        self.event_sender({"event": "audio_snapshot", "snapshot": snapshot})

    def shutdown(self) -> None:
        if self.thread is None:
            return
        self.queue.put(_STOP)
        self.thread.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)


_watcher: AudioWatcher | None = None
_action_worker: AudioActionWorker | None = None


def _get_watcher() -> AudioWatcher:
    global _watcher
    if _watcher is None:
        _watcher = AudioWatcher()
    return _watcher


def _get_action_worker() -> AudioActionWorker:
    global _action_worker
    if _action_worker is None:
        _action_worker = AudioActionWorker()
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


def _validate_value(action: str, target: str, value: Any, snapshot: dict[str, Any]) -> None:
    if action.endswith("_volume"):
        if isinstance(value, bool):
            raise ValueError("volume must be between 0 and 150")
        try:
            volume = float(value)
        except (TypeError, ValueError) as exc:
            raise ValueError("volume must be between 0 and 150") from exc
        if not 0 <= volume <= 150:
            raise ValueError("volume must be between 0 and 150")
    elif action.endswith("_mute"):
        if not isinstance(value, bool):
            raise ValueError("mute value must be a boolean")
    elif action == "move_stream":
        sink = _require_name(value, "output")
        if not any(item.get("name") == sink for item in snapshot.get("sinks", [])):
            raise ValueError(f"unknown output: {sink}")
    elif action in ("set_sink_port", "set_source_port"):
        port = _require_name(value, "port")
        items = snapshot["sinks"] if action == "set_sink_port" else snapshot["sources"]
        item = next((item for item in items if item.get("name") == target), {})
        if not any(candidate.get("name") == port for candidate in item.get("ports", [])):
            raise ValueError(f"unknown port: {port}")
    elif action == "set_card_profile":
        profile = _require_name(value, "profile")
        card = next((item for item in snapshot.get("cards", []) if item.get("name") == target), {})
        if profile not in card.get("profiles", []):
            raise ValueError(f"unknown profile: {profile}")


def run_audio_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown audio action: {action}")
    target = _require_name(params.get("target"), "target")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    snapshot = load_snapshot()
    if not target_present(action, target, snapshot):
        noun = "output" if "sink" in action or action == "move_stream" else "target"
        raise ValueError(f"unknown {noun}: {target}")
    _validate_value(action, target, params.get("value"), snapshot)
    request = dict(params)
    request.update({
        "action": action, "target": target, "action_id": action_id,
        "generation": generation,
    })
    _get_action_worker().submit(request)
    return {"queued": True, "action_id": action_id, "generation": generation}


def set_audio_automation(params: dict[str, Any]) -> dict[str, Any]:
    allowed = {"bluetooth_auto_switch", "enabled"}
    unknown = set(params) - allowed
    if unknown:
        raise ValueError(f"unknown automation setting: {sorted(unknown)[0]}")
    if not params or any(not isinstance(value, bool) for value in params.values()):
        raise ValueError("automation settings must be booleans")
    config = audio_core.load_auto_switch_config()
    config.update(params)
    audio_core.save_auto_switch_config(config)
    service_control.synchronize_service(config)
    return load_snapshot()


def set_audio_priority(params: dict[str, Any]) -> dict[str, Any]:
    priority = params.get("priority")
    if set(params) != {"priority"} or not isinstance(priority, list) or any(
        not isinstance(name, str) or not name for name in priority
    ):
        raise ValueError("priority must be a list of output names")
    # Keep offline/remembered names. AutoSwitchPolicy already skips sinks that
    # are absent or suspended when choosing an output.
    ordered = list(dict.fromkeys(priority))
    config = audio_core.load_auto_switch_config()
    existing = config.get("output_priority_labels", {})
    if not isinstance(existing, dict):
        existing = {}
    config["output_priority"] = ordered
    config["output_priority_labels"] = audio_core.resolve_output_priority_labels(
        ordered, existing=existing,
    )
    audio_core.save_auto_switch_config(config)
    service_control.synchronize_service(config)
    return load_snapshot()


def enable_audio_autoswitch_service(params: dict[str, Any]) -> dict[str, Any]:
    if set(params) - {"enable", "dismiss_prompt"}:
        raise ValueError("unknown service setting")
    enable = params.get("enable", True)
    dismiss_prompt = params.get("dismiss_prompt", True)
    if not isinstance(enable, bool) or not isinstance(dismiss_prompt, bool):
        raise ValueError("service settings must be booleans")
    result = (
        service_control.set_service_enabled(True, reload_daemon=True)
        if enable else {"ok": True, "message": "Service setup postponed"}
    )
    if dismiss_prompt:
        config = service_control.dismiss_service_prompt(audio_core.load_auto_switch_config())
        audio_core.save_auto_switch_config(config)
    status = service_control.service_status()
    snapshot = load_snapshot()
    protocol.send_event({
        "event": "audio_service_status", "status": status,
        "message": result["message"],
    })
    return {**result, "status": status, "snapshot": snapshot}


def get_audio_autoswitch_service_status(_params: dict[str, Any]) -> dict[str, Any]:
    config = audio_core.load_auto_switch_config()
    status = service_control.service_status()
    return {
        "status": status,
        "should_prompt": service_control.should_prompt_migration(config, status),
    }


def get_audio_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def start_audio_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_audio_watch(_params: dict[str, Any]) -> dict[str, Any]:
    stopped = _watcher is None or _watcher.stop()
    return {
        "ok": stopped,
        "message": "" if stopped else "Audio watcher is still stopping",
    }


def shutdown() -> None:
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_audio_snapshot", get_audio_snapshot)
protocol.register("start_audio_watch", start_audio_watch)
protocol.register("stop_audio_watch", stop_audio_watch)
protocol.register("run_audio_action", run_audio_action)
protocol.register("set_audio_automation", set_audio_automation)
protocol.register("set_audio_priority", set_audio_priority)
protocol.register("enable_audio_autoswitch_service", enable_audio_autoswitch_service)
protocol.register("get_audio_autoswitch_service_status", get_audio_autoswitch_service_status)
