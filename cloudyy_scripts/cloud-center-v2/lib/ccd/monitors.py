"""
Cloud Center — lib/ccd/monitors.py
QML-facing wrapper around lib/monitor_editor.py's module-level hyprctl/Lua
functions (MonitorInfo, _fetch_monitors, _build_monitor_line,
_write_monitor_line, _apply_monitor_line — all plain functions, no GTK
coupling; only DisplayLayoutPreview and MonitorEditorPage further down that
file are GTK-specific, so this module reuses the data layer directly).
"""
from __future__ import annotations

import copy
import dataclasses
import logging
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import uuid
from typing import Callable

import lib.monitor_editor as me
from lib.ccd import protocol
from lib.ccd import monitor_layout

log = logging.getLogger(__name__)

TRANSFORMS = [{"id": tid, "label": label} for tid, label in me.TRANSFORM_LABELS]

ADVANCED_DEFAULTS = {
    "bitdepth": 8,
    "cm": "srgb",
    "sdr_eotf": "default",
    "sdrbrightness": 1.0,
    "sdrsaturation": 1.0,
    "vrr": 0,
    "icc": "",
}


class MonitorSession:
    """Own one monitor-page snapshot and its temporary apply transaction."""

    def __init__(
        self,
        *,
        config_path: Path,
        fetch_layout: Callable[[], list[dict]],
        apply_layout: Callable[[list[dict]], tuple[bool, str]],
        activate_config: Callable[[], tuple[bool, str]],
        timer_factory=threading.Timer,
        token_factory=lambda: uuid.uuid4().hex,
        event_sender=protocol.send_event,
        clock=time.time,
    ) -> None:
        self.config_path = Path(config_path)
        self.fetch_layout = fetch_layout
        self.apply_layout = apply_layout
        self.activate_config = activate_config
        self.timer_factory = timer_factory
        self.token_factory = token_factory
        self.event_sender = event_sender
        self.clock = clock
        self.config_snapshot: bytes | None = None
        self.live_snapshot: list[dict] | None = None
        self.tested_layout: list[dict] | None = None
        self.token: str | None = None
        self.timer = None
        self.lock = threading.RLock()

    def open(self) -> dict:
        with self.lock:
            if self.config_snapshot is not None:
                self.close()
            try:
                self.config_snapshot = self.config_path.read_bytes()
            except FileNotFoundError:
                self.config_snapshot = b""
            except OSError as exc:
                return {"ok": False, "message": f"Could not snapshot monitor config: {exc}"}
            self.live_snapshot = copy.deepcopy(self.fetch_layout())
            return {"ok": True, "monitors": copy.deepcopy(self.live_snapshot)}

    def test_layout(self, drafts: list[dict], timeout: int = 15) -> dict:
        with self.lock:
            if self.config_snapshot is None or self.live_snapshot is None:
                return {"ok": False, "message": "monitor session is not open"}
            if self.token is not None:
                return {"ok": False, "message": "a display confirmation is already active"}
            if not any(bool(draft.get("enabled", True)) for draft in drafts):
                return {"ok": False, "message": "At least one display must remain enabled"}

            staged = copy.deepcopy(drafts)
            ok, message = self.apply_layout(staged)
            if not ok:
                self.apply_layout(copy.deepcopy(self.live_snapshot))
                return {"ok": False, "message": message}

            self.tested_layout = staged
            self.token = str(self.token_factory())
            deadline = self.clock() + timeout
            token = self.token
            self.timer = self.timer_factory(timeout, lambda: self._timeout(token))
            if hasattr(self.timer, "daemon"):
                self.timer.daemon = True
            self.timer.start()
            return {
                "ok": True,
                "message": message,
                "token": self.token,
                "deadline": deadline,
            }

    def keep(self, token: str) -> dict:
        with self.lock:
            if not self._token_matches(token):
                return {"ok": False, "message": "display confirmation is no longer active"}
            self._cancel_timer()
            assert self.config_snapshot is not None
            assert self.tested_layout is not None
            original = self.config_snapshot
            rendered = monitor_layout.render_layout_config(
                original.decode("utf-8"), self.tested_layout,
            ).encode("utf-8")
            try:
                self._atomic_write(rendered)
                ok, message = self.activate_config()
                if not ok:
                    raise OSError(message)
            except Exception as exc:
                try:
                    self._atomic_write(original)
                finally:
                    self.apply_layout(copy.deepcopy(self.live_snapshot or []))
                    self._clear_transaction()
                return {"ok": False, "message": f"Could not persist monitor layout: {exc}"}

            self.config_snapshot = rendered
            self.live_snapshot = copy.deepcopy(self.tested_layout)
            self._clear_transaction()
            return {"ok": True, "message": "Display layout saved"}

    def revert(self, token: str | None = None) -> dict:
        with self.lock:
            if token is not None and not self._token_matches(token):
                return {"ok": False, "message": "display confirmation is no longer active"}
            return self._revert_locked()

    def close(self) -> dict:
        with self.lock:
            result = self._revert_locked() if self.token is not None else {"ok": True, "message": "Draft discarded"}
            self.config_snapshot = None
            self.live_snapshot = None
            self._clear_transaction()
            return result

    def _timeout(self, token: str) -> None:
        with self.lock:
            if not self._token_matches(token):
                return
            result = self._revert_locked()
            self.event_sender({
                "event": "monitor_layout",
                "state": "reverted",
                "message": result.get("message", "Display layout restored"),
            })

    def _revert_locked(self) -> dict:
        self._cancel_timer()
        if self.token is None or self.live_snapshot is None:
            self._clear_transaction()
            return {"ok": True, "message": "Draft discarded"}
        ok, message = self.apply_layout(copy.deepcopy(self.live_snapshot))
        self._clear_transaction()
        return {"ok": ok, "message": message if not ok else "Previous display layout restored"}

    def _token_matches(self, token: str) -> bool:
        return self.token is not None and token == self.token

    def _cancel_timer(self) -> None:
        if self.timer is not None:
            self.timer.cancel()
            self.timer = None

    def _clear_transaction(self) -> None:
        self._cancel_timer()
        self.tested_layout = None
        self.token = None

    def _atomic_write(self, content: bytes) -> None:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=str(self.config_path.parent))
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            Path(temporary).replace(self.config_path)
        except Exception:
            try:
                Path(temporary).unlink(missing_ok=True)
            finally:
                raise


def build_drafts(monitors: list[me.MonitorInfo], rules: dict[str, str]) -> list[dict]:
    """Merge live monitor state with advanced values only available in config."""
    drafts: list[dict] = []
    for monitor in monitors:
        draft = dataclasses.asdict(monitor)
        draft.update({
            "mode": monitor.current_mode_str,
            "enabled": not monitor.disabled,
            "mirror_of": "" if monitor.mirror_of.lower() == "none" else monitor.mirror_of,
            "workspaces": list(monitor.assigned_workspaces),
            **ADVANCED_DEFAULTS,
        })
        persisted = monitor_layout.parse_monitor_line(rules.get(monitor.name, ""))
        for field in ADVANCED_DEFAULTS:
            if field in persisted:
                draft[field] = persisted[field]
        drafts.append(draft)
    return drafts


def _fetch_layout() -> list[dict]:
    monitor_data, _migrations = me._fetch_monitors()
    rules, _workspaces = me._parse_conf()
    return build_drafts(monitor_data, rules)


def _run_result(result: subprocess.CompletedProcess) -> tuple[bool, str]:
    response = ((result.stdout or "").strip() or (result.stderr or "").strip())
    lowered = response.lower()
    ok = result.returncode == 0 and not (
        lowered and "ok" not in lowered
        and any(token in lowered for token in ("error", "failed", "invalid"))
    )
    if ok:
        return True, response or "ok"
    return False, response or f"command exited with status {result.returncode}"


def _apply_layout(drafts: list[dict]) -> tuple[bool, str]:
    """Apply a complete monitor draft in one Hyprland Lua evaluation."""
    script = "; ".join(monitor_layout.build_monitor_line(draft) for draft in drafts)
    if not script:
        return False, "No monitor rules to apply"
    try:
        result = subprocess.run(
            ["hyprctl", "eval", script],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except Exception as exc:
        return False, str(exc)
    return _run_result(result)


def _activate_config() -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["hcm", "activate", "monitors"],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except Exception as exc:
        return False, str(exc)
    return _run_result(result)


SESSION = MonitorSession(
    config_path=me.MONITORS_CONF,
    fetch_layout=_fetch_layout,
    apply_layout=_apply_layout,
    activate_config=_activate_config,
)


def list_monitors(params: dict) -> dict:
    return {
        "monitors": _fetch_layout(),
        "transforms": TRANSFORMS,
    }


def open_monitor_session(params: dict) -> dict:
    result = SESSION.open()
    result["transforms"] = TRANSFORMS
    return result


def test_monitor_layout(params: dict) -> dict:
    drafts = params.get("monitors", [])
    if not isinstance(drafts, list):
        return {"ok": False, "message": "monitors must be a list"}
    return SESSION.test_layout(drafts, timeout=15)


def keep_monitor_layout(params: dict) -> dict:
    return SESSION.keep(str(params.get("token", "")))


def revert_monitor_layout(params: dict) -> dict:
    return SESSION.revert(str(params.get("token", "")))


def close_monitor_session(params: dict) -> dict:
    return SESSION.close()


def set_dpms(params: dict) -> dict:
    name = str(params.get("name", "")).strip()
    if not name:
        return {"ok": False, "message": "monitor name is required"}
    action = "on" if bool(params.get("enabled", True)) else "off"
    escaped_name = name.replace("\\", "\\\\").replace('"', '\\"')
    script = f'hl.dispatch(hl.dsp.dpms({{ action = "{action}", monitor = "{escaped_name}" }}))'
    try:
        result = subprocess.run(
            ["hyprctl", "eval", script],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:
        return {"ok": False, "message": str(exc)}
    ok, message = _run_result(result)
    return {"ok": ok, "message": message}


def shutdown() -> None:
    SESSION.close()


def apply_monitor(params: dict) -> dict:
    name = str(params.get("name", ""))
    if not name:
        return {"ok": False, "message": "monitor name is required"}

    enabled = bool(params.get("enabled", True))
    workspaces = [str(w) for w in params.get("workspaces", [])]
    line = me._build_monitor_line(
        name=name,
        mode=str(params.get("mode", "")),
        pos_x=int(params.get("pos_x", 0)),
        pos_y=int(params.get("pos_y", 0)),
        scale=float(params.get("scale", 1.0)),
        transform=int(params.get("transform", 0)),
        enabled=enabled,
        mirror_of=str(params.get("mirror_of", "")),
    )

    ok, message = me._apply_monitor_line(line)
    if not ok:
        return {"ok": False, "message": message}

    # Live apply succeeded; persist so it survives reload/reboot.
    me._write_monitor_line(name, line, workspaces)
    return {"ok": True, "message": message}


def add_headless(params: dict) -> dict:
    try:
        result = subprocess.run(
            ["hyprctl", "output", "create", "headless"],
            capture_output=True, text=True, timeout=5,
        )
    except Exception as e:
        return {"ok": False, "message": str(e)}
    ok = result.returncode == 0
    return {"ok": ok, "message": (result.stdout or result.stderr or "").strip()}


def remove_headless(params: dict) -> dict:
    name = str(params.get("name", ""))
    if not name:
        return {"ok": False, "message": "monitor name is required"}
    try:
        result = subprocess.run(
            ["hyprctl", "output", "remove", name],
            capture_output=True, text=True, timeout=5,
        )
    except Exception as e:
        return {"ok": False, "message": str(e)}
    ok = result.returncode == 0
    return {"ok": ok, "message": (result.stdout or result.stderr or "").strip()}


def reload_hyprland(params: dict) -> dict:
    result = subprocess.run(["hyprctl", "reload"], capture_output=True, text=True, check=False)
    return {"ok": result.returncode == 0}


protocol.register("list_monitors", list_monitors)
protocol.register("apply_monitor", apply_monitor)
protocol.register("add_headless_monitor", add_headless)
protocol.register("remove_headless_monitor", remove_headless)
protocol.register("reload_hyprland", reload_hyprland)
protocol.register("open_monitor_session", open_monitor_session)
protocol.register("test_monitor_layout", test_monitor_layout)
protocol.register("keep_monitor_layout", keep_monitor_layout)
protocol.register("revert_monitor_layout", revert_monitor_layout)
protocol.register("close_monitor_session", close_monitor_session)
protocol.register("set_monitor_dpms", set_dpms)
