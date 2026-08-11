"""Cloud Center — lib/ccd/recording.py
GTK-free ccd protocol adapter for the Recording page: snapshot store, watcher,
and action worker wrapping lib/recording_core.py.
"""
from __future__ import annotations

import copy
import logging
import queue
import shlex
import subprocess
import threading
from typing import Any, Callable

from lib import recording_core
from lib.ccd import protocol

log = logging.getLogger(__name__)
SHUTDOWN_TIMEOUT_SECONDS = 2
WATCH_INTERVAL_SECONDS = 2.0
ALLOWED_ACTIONS = recording_core.ALLOWED_ACTIONS
SCREENSHOT_CAPTURE_BIN = "cloudyy-screenshot-capture"
_STOP = object()


class SnapshotStore:
    def __init__(self, loader: Callable[[], dict[str, Any]] | None = None) -> None:
        self.loader = loader or recording_core.build_recording_snapshot
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
                    "settings": {},
                    "audio_inputs": {"mics": [], "desktops": []},
                    "recording": {"active": False, "out_file": "", "selection": ""},
                    "gallery": [],
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


class RecordingWatcher:
    def __init__(
        self,
        interval: float = WATCH_INTERVAL_SECONDS,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.interval = interval
        self.emitter = emitter or (
            lambda snapshot: protocol.send_event(
                {"event": "recording_snapshot", "snapshot": snapshot}
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
                target=self._run, name="recording-watch", daemon=True,
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
                log.debug("recording watch emit failed: %s", exc)
            self._stop.wait(self.interval)


def _hypr_exec_cmd(cmd: str) -> list[str]:
    """Match bindings.lua: hl.dispatch(hl.dsp.exec_cmd("…")) via hyprctl eval."""
    escaped = cmd.replace("\\", "\\\\").replace('"', '\\"')
    return [
        "hyprctl",
        "eval",
        f'hl.dispatch(hl.dsp.exec_cmd("{escaped}"))',
    ]


def _trigger_capture(flags: list[str]) -> dict[str, Any]:
    """Launch capture detached via Hyprland so Cloud Center doesn't own focus/grab."""
    argv = [SCREENSHOT_CAPTURE_BIN] + list(flags)
    # Same entry point as bindings.lua Print / Shift+Print / Alt+Print.
    # Plain `hyprctl dispatch exec` is broken on Lua Hyprland.
    cmd = " ".join(shlex.quote(part) for part in argv)
    try:
        subprocess.Popen(
            _hypr_exec_cmd(cmd),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return {"ok": True, "message": ""}
    except OSError:
        try:
            subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return {"ok": True, "message": ""}
        except OSError as exc:
            return {"ok": False, "message": str(exc)}


def _run_recording_action(action: str, value: Any) -> dict[str, Any]:
    if action == "set_setting":
        if not isinstance(value, dict):
            raise ValueError("set_setting value must be an object with key/value")
        return recording_core.save_setting(value.get("key"), value.get("value"))
    if action == "trigger_screenshot":
        if value not in ("ephemeral", "save"):
            raise ValueError('screenshot mode must be "ephemeral" or "save"')
        flag = "--screenshot-save" if value == "save" else "--screenshot"
        return _trigger_capture([flag])
    if action == "trigger_record_toggle":
        state = recording_core._parse_recording_state()
        if not state.get("active"):
            resolved = recording_core.resolve_audio_source(recording_core.load_settings())
            if not resolved.get("ok"):
                return {"ok": False, "message": str(resolved.get("message", ""))}
        return _trigger_capture(["--record"])
    if action in ("open", "edit", "copy", "delete", "reveal"):
        settings = recording_core.load_settings()
        return recording_core.run_file_action(
            action, str(value), edit_command=str(settings.get("edit_command") or ""),
        )
    if action == "ensure_thumb":
        return recording_core.ensure_thumb(str(value))
    raise ValueError(f"unknown recording action: {action}")


class ActionWorker:
    def __init__(
        self,
        runner: Callable[..., dict[str, Any]] | None = None,
        emitter: Callable[[dict[str, Any]], None] | None = None,
        snapshot_loader: Callable[[], dict[str, Any]] | None = None,
    ) -> None:
        self.runner = runner or _run_recording_action
        self.emitter = emitter or protocol.send_event
        self.snapshot_loader = snapshot_loader or load_snapshot
        self._queue: queue.Queue[Any] = queue.Queue()
        self._thread = threading.Thread(
            target=self._run, name="recording-actions", daemon=True,
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
                "event": "recording_action_done",
                "action_id": action_id,
                "target": target,
                "generation": generation,
                "ok": ok,
                "stale_target": False,
                "message": message,
            })
            try:
                self.emitter({
                    "event": "recording_snapshot",
                    "snapshot": self.snapshot_loader(),
                })
            except Exception as exc:
                log.debug("recording post-action snapshot failed: %s", exc)


_snapshots = SnapshotStore()
_watcher: RecordingWatcher | None = None
_action_worker: ActionWorker | None = None
_worker_lock = threading.Lock()


def load_snapshot() -> dict[str, Any]:
    return _snapshots.load()


def _get_watcher() -> RecordingWatcher:
    global _watcher
    with _worker_lock:
        if _watcher is None:
            _watcher = RecordingWatcher()
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


def run_recording_action(params: dict[str, Any]) -> dict[str, Any]:
    action = params.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown recording action: {action}")
    raw_action_id = params.get("action_id")
    if raw_action_id is None or raw_action_id == "":
        raise ValueError("action_id is required")
    action_id = str(raw_action_id)
    generation = _coerce_generation(params.get("generation", 0))
    value = params.get("value")
    if action == "trigger_screenshot" and value not in ("ephemeral", "save"):
        raise ValueError('screenshot mode must be "ephemeral" or "save"')
    target = str(params.get("target") or action)
    _get_action_worker().submit({
        "action": action,
        "target": target,
        "value": value,
        "action_id": action_id,
        "generation": generation,
    })
    return {"queued": True, "action_id": action_id, "generation": generation}


def get_recording_snapshot(_params: dict[str, Any]) -> dict[str, Any]:
    return load_snapshot()


def start_recording_watch(_params: dict[str, Any]) -> dict[str, Any]:
    _get_watcher().start()
    return load_snapshot()


def stop_recording_watch(_params: dict[str, Any]) -> dict[str, Any]:
    stopped = _watcher is None or _watcher.stop()
    return {
        "ok": stopped,
        "message": "" if stopped else "Recording watcher is still stopping",
    }


def shutdown() -> None:
    if _watcher is not None:
        _watcher.stop()
    if _action_worker is not None:
        _action_worker.shutdown()


protocol.register("get_recording_snapshot", get_recording_snapshot)
protocol.register("start_recording_watch", start_recording_watch)
protocol.register("stop_recording_watch", stop_recording_watch)
protocol.register("run_recording_action", run_recording_action)
