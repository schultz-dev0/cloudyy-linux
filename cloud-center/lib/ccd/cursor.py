"""Transactional Hyprland 0.55 cursor settings for the QML Cloud Center."""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading
import time
from typing import Callable, Iterable
import uuid

from lib.ccd import protocol


STATE_PREFIX = "-- @cloud-center-state = "
MANAGED_BEGIN = "-- --- Cloud Center managed cursor settings ---"
MANAGED_END = "-- --- End Cloud Center managed cursor settings ---"
DEFAULT_HYPRCURSOR_THEME = "Bibata-Modern-Ice"
DEFAULT_CURSOR_SIZE = 24
XCURSOR_THEME_OVERRIDES = {
    "macOS-hypr": "macOS",
    "macOS-hypr_white": "macOS-White",
}

HYPR_DIR = Path.home() / ".config" / "hypr"
CURSOR_PATH = HYPR_DIR / "cursor.lua"
VARIABLES_PATH = HYPR_DIR / "variables.lua"
WINDOWRULES_PATH = HYPR_DIR / "windowrules.lua"
AUTOSTART_PATH = HYPR_DIR / "autostart.lua"
THEME_ROOTS = (
    Path("/usr/share/icons"),
    Path("/usr/local/share/icons"),
    Path.home() / ".local/share/icons",
    Path.home() / ".icons",
)


def _setting(
    key: str,
    section: str,
    kind: str,
    default: object,
    title: str,
    description: str,
    **extra: object,
) -> dict:
    return {
        "key": key,
        "section": section,
        "type": kind,
        "default": default,
        "title": title,
        "description": description,
        **extra,
    }


CURSOR_SCHEMA = [
    _setting("enable_hyprcursor", "appearance", "bool", True,
             "Enable Hyprcursor", "Use Hyprland's vector cursor format"),
    _setting("no_warps", "movement", "bool", False,
             "Disable cursor warps", "Do not move the cursor automatically when focus changes"),
    _setting("persistent_warps", "movement", "bool", False,
             "Persistent position", "Return to the cursor's last position inside a refocused window"),
    _setting("warp_on_change_workspace", "movement", "enum", 0,
             "Workspace changes", "Move to the last focused window after changing workspace",
             values=[0, 1, 2], labels=["Disabled", "Enabled", "Force"]),
    _setting("warp_on_toggle_special", "movement", "enum", 0,
             "Special workspaces", "Move to the last focused window when toggling a special workspace",
             values=[0, 1, 2], labels=["Disabled", "Enabled", "Force"]),
    _setting("default_monitor", "movement", "string", "",
             "Default monitor", "Monitor where the cursor starts", options="monitors"),
    _setting("warp_back_after_non_mouse_input", "movement", "bool", False,
             "Return after non-mouse input", "Restore the pointer after touch or tablet input moves it"),
    _setting("inactive_timeout", "visibility", "float", 0.0,
             "Inactive timeout", "Seconds before hiding the cursor; 0 keeps it visible",
             minimum=0.0, maximum=20.0, step=0.5),
    _setting("hide_on_key_press", "visibility", "bool", False,
             "Hide while typing", "Hide until the pointer moves after a key press"),
    _setting("hide_on_touch", "visibility", "bool", True,
             "Hide after touch", "Hide until mouse input follows touchscreen input"),
    _setting("hide_on_tablet", "visibility", "bool", False,
             "Hide after tablet input", "Hide until mouse input follows tablet input"),
    _setting("invisible", "visibility", "bool", False,
             "Invisible cursor", "Never render the cursor", dangerous=True),
    _setting("zoom_factor", "magnification", "float", 1.0,
             "Zoom factor", "Magnify the desktop around the cursor",
             minimum=1.0, maximum=10.0, step=0.1),
    _setting("zoom_rigid", "magnification", "bool", False,
             "Rigid tracking", "Keep the cursor centered while zooming"),
    _setting("zoom_detached_camera", "magnification", "bool", True,
             "Detached camera", "Only move the camera when the pointer reaches an edge"),
    _setting("zoom_disable_aa", "magnification", "bool", False,
             "Pixelated zoom", "Disable antialiasing while magnified"),
    _setting("sync_gsettings_theme", "advanced", "bool", True,
             "Synchronize GTK cursor", "Ask Hyprland to synchronize cursor appearance through GSettings"),
    _setting("no_hardware_cursors", "advanced", "enum", 2,
             "Hardware cursors", "Choose when Hyprland avoids hardware cursors",
             values=[0, 1, 2], labels=["Use when possible", "Disable", "Auto"]),
    _setting("use_cpu_buffer", "advanced", "enum", 2,
             "CPU cursor buffer", "Use a CPU buffer for hardware cursors",
             values=[0, 1, 2], labels=["Off", "On", "Auto"]),
    _setting("no_break_fs_vrr", "advanced", "enum", 2,
             "Fullscreen VRR protection", "Avoid cursor-triggered frames in fullscreen VRR apps",
             values=[0, 1, 2], labels=["Off", "On", "Auto"]),
    _setting("min_refresh_rate", "advanced", "int", 24,
             "Minimum cursor refresh", "Lowest refresh rate while VRR protection is active",
             minimum=10, maximum=500, step=1),
    _setting("hotspot_padding", "advanced", "int", 0,
             "Edge padding", "Logical pixels kept between the cursor hotspot and screen edges",
             minimum=0, maximum=20, step=1),
]


def _manifest_value(text: str, key: str) -> str:
    match = re.search(rf"(?m)^\s*{re.escape(key)}\s*=\s*(.+?)\s*$", text)
    if not match:
        return ""
    return match.group(1).strip().strip('"\'')


def discover_hyprcursor_themes(roots: Iterable[Path]) -> list[dict]:
    """Return installed Hyprcursor themes from immediate children of roots."""
    found: dict[str, dict] = {}
    for root in roots:
        path = Path(root)
        if not path.is_dir():
            continue
        try:
            children = sorted(path.iterdir(), key=lambda child: child.name.casefold())
        except OSError:
            continue
        for child in children:
            manifest = child / "manifest.hl"
            if not child.is_dir() or not manifest.is_file():
                continue
            try:
                text = manifest.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            name = _manifest_value(text, "name") or child.name
            found.setdefault(name, {
                "id": name,
                "name": name,
                "description": _manifest_value(text, "description"),
            })
    return sorted(found.values(), key=lambda item: item["name"].casefold())


def _state_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def _lua_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def _without_managed_cursor_content(existing: str) -> str:
    lines = existing.splitlines()
    begin_count = lines.count(MANAGED_BEGIN)
    end_count = lines.count(MANAGED_END)
    if begin_count != end_count or begin_count > 1:
        raise ValueError("Malformed or duplicate managed cursor markers")
    kept: list[str] = []
    in_managed = False
    for line in lines:
        if line == MANAGED_BEGIN:
            if in_managed:
                raise ValueError("Malformed managed cursor markers")
            in_managed = True
            continue
        if line == MANAGED_END:
            if not in_managed:
                raise ValueError("Malformed managed cursor markers")
            in_managed = False
            continue
        if in_managed or line.startswith(STATE_PREFIX):
            continue
        kept.append(line)
    return "\n".join(kept).strip()


def render_cursor_config(existing: str, values: dict[str, object]) -> str:
    """Render one managed cursor block while preserving Lua outside it."""
    normalized = {
        item["key"]: values.get(item["key"], item["default"])
        for item in CURSOR_SCHEMA
    }
    state = {
        f"cursor:{key}": _state_value(value)
        for key, value in normalized.items()
    }
    body = _without_managed_cursor_content(existing)
    if not body:
        body = "-- Cloud Center user override file for cursor configuration."
    managed_lines = [
        MANAGED_BEGIN,
        "hl.config({",
        "    cursor = {",
        *[
            f"        {item['key']} = {_lua_value(normalized[item['key']])},"
            for item in CURSOR_SCHEMA
        ],
        "    },",
        "})",
        MANAGED_END,
    ]
    return "\n".join([
        body.splitlines()[0],
        f"{STATE_PREFIX}{json.dumps(state, sort_keys=True)}",
        *body.splitlines()[1:],
        "",
        *managed_lines,
        "",
    ])


def merge_cursor_environment(
    existing: list[dict], theme: str, size: int,
) -> list[dict]:
    """Replace cursor-owned environment entries for both cursor systems."""
    owned = {"XCURSOR_THEME", "XCURSOR_SIZE", "HYPRCURSOR_THEME", "HYPRCURSOR_SIZE"}
    merged = [
        {"name": str(item.get("name", "")), "value": str(item.get("value", ""))}
        for item in existing
        if str(item.get("name", "")) not in owned
    ]
    merged.extend([
        {"name": "XCURSOR_THEME", "value": xcursor_theme_for(theme)},
        {"name": "XCURSOR_SIZE", "value": str(int(size))},
        {"name": "HYPRCURSOR_THEME", "value": str(theme)},
        {"name": "HYPRCURSOR_SIZE", "value": str(int(size))},
    ])
    return merged


def xcursor_theme_for(hyprcursor_theme: str) -> str:
    """Return the matching XCursor name for an installed Hyprcursor theme."""
    return XCURSOR_THEME_OVERRIDES.get(hyprcursor_theme, hyprcursor_theme)


def parse_live_value(setting: dict, payload: dict) -> object:
    kind = setting["type"]
    if kind == "bool":
        return bool(payload.get("bool", setting["default"]))
    if kind in {"enum", "int"}:
        return int(payload.get("int", setting["default"]))
    if kind == "float":
        return float(payload.get("float", setting["default"]))
    value = str(payload.get("str", setting["default"]))
    return "" if value == "[[EMPTY]]" else value


def _snapshot(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def _atomic_write(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        Path(temporary).replace(path)
    except Exception:
        Path(temporary).unlink(missing_ok=True)
        raise


def _restore(path: Path, content: bytes | None) -> None:
    if content is None:
        path.unlink(missing_ok=True)
    else:
        _atomic_write(path, content)


class CursorSession:
    """Own live cursor previews and the files changed by one Cursor page."""

    def __init__(
        self,
        *,
        cursor_path: Path,
        variables_path: Path,
        fetch_values: Callable[[], dict[str, object]],
        fetch_appearance: Callable[[], tuple[str, int]],
        fetch_themes: Callable[[], list[dict]],
        fetch_monitors: Callable[[], list[str]],
        apply_option: Callable[[str, object], tuple[bool, str]],
        apply_theme: Callable[[str, int], tuple[bool, str]],
        # ponytail: hcm binary is retired, nothing to activate post single-file
        # consolidation; kept as an overridable hook since apply() still calls it.
        activate_cursor: Callable[[], tuple[bool, str]] = lambda: (True, "ok"),
        persist_cursor: Callable[[dict[str, object]], None],
        persist_environment: Callable[[str, int], None],
        additional_paths: Iterable[Path] = (),
        timer_factory=threading.Timer,
        token_factory=lambda: uuid.uuid4().hex,
        event_sender=lambda _event: None,
        clock=time.time,
    ) -> None:
        self.cursor_path = Path(cursor_path)
        self.variables_path = Path(variables_path)
        self.fetch_values = fetch_values
        self.fetch_appearance = fetch_appearance
        self.fetch_themes = fetch_themes
        self.fetch_monitors = fetch_monitors
        self.apply_option = apply_option
        self.apply_theme = apply_theme
        self.activate_cursor = activate_cursor
        self.persist_cursor = persist_cursor
        self.persist_environment = persist_environment
        self.transaction_paths = tuple(dict.fromkeys((
            self.cursor_path,
            self.variables_path,
            *(Path(path) for path in additional_paths),
        )))
        self.timer_factory = timer_factory
        self.token_factory = token_factory
        self.event_sender = event_sender
        self.clock = clock
        self.lock = threading.RLock()
        self.snapshots: dict[Path, bytes | None] | None = None
        self.baseline_values: dict[str, object] | None = None
        self.draft_values: dict[str, object] | None = None
        self.baseline_theme = ""
        self.baseline_size = 24
        self.draft_theme = ""
        self.draft_size = 24
        self.invisible_token: str | None = None
        self.invisible_previous: object = False
        self.invisible_timer = None

    @property
    def is_open(self) -> bool:
        return self.snapshots is not None

    def _take_snapshots(self) -> dict[Path, bytes | None]:
        return {
            path: _snapshot(path)
            for path in self.transaction_paths
        }

    def open(self) -> dict:
        with self.lock:
            if self.is_open:
                closed = self.close()
                if not closed["ok"]:
                    return {
                        "ok": False,
                        "message": "Could not replace the existing Cursor session: "
                        + closed["message"],
                    }
            try:
                fetched = self.fetch_values()
                values = {
                    item["key"]: fetched.get(item["key"], item["default"])
                    for item in CURSOR_SCHEMA
                }
                theme, size = self.fetch_appearance()
                snapshots = self._take_snapshots()
                themes = self.fetch_themes()
                monitors = self.fetch_monitors()
            except Exception as exc:
                return {"ok": False, "message": f"Could not open Cursor settings: {exc}"}

            self.snapshots = snapshots
            self.baseline_values = copy.deepcopy(values)
            self.draft_values = copy.deepcopy(values)
            self.baseline_theme = self.draft_theme = str(theme)
            self.baseline_size = self.draft_size = int(size)
            return {
                "ok": True,
                "values": copy.deepcopy(values),
                "theme": self.draft_theme,
                "size": self.draft_size,
                "themes": themes,
                "monitors": monitors,
                "schema": copy.deepcopy(CURSOR_SCHEMA),
            }

    def preview_option(self, key: str, value: object) -> dict:
        with self.lock:
            if not self.is_open or self.draft_values is None:
                return {"ok": False, "message": "Cursor session is not open"}
            if key not in self.draft_values:
                return {"ok": False, "message": f"Unknown cursor setting: {key}"}
            previous = self.draft_values[key]
            ok, message = self.apply_option(key, value)
            if not ok:
                return {"ok": False, "message": message, "value": previous}

            self.draft_values[key] = value
            response = {
                "ok": True,
                "message": message,
                "value": value,
                "dirty": self._dirty(),
            }
            if key == "invisible":
                if bool(value) and not bool(previous):
                    response.update(self._start_invisible_confirmation(previous))
                elif not bool(value):
                    self._clear_invisible_confirmation()
            return response

    def preview_appearance(self, theme: str, size: int) -> dict:
        with self.lock:
            if not self.is_open:
                return {"ok": False, "message": "Cursor session is not open"}
            previous = (self.draft_theme, self.draft_size)
            ok, message = self.apply_theme(str(theme), int(size))
            if not ok:
                return {
                    "ok": False,
                    "message": message,
                    "theme": previous[0],
                    "size": previous[1],
                }
            self.draft_theme = str(theme)
            self.draft_size = int(size)
            return {
                "ok": True,
                "message": message,
                "theme": self.draft_theme,
                "size": self.draft_size,
                "dirty": self._dirty(),
            }

    def keep_invisible(self, token: str) -> dict:
        with self.lock:
            if self.invisible_token is None or token != self.invisible_token:
                return {"ok": False, "message": "Cursor visibility confirmation is no longer active"}
            self._clear_invisible_confirmation()
            return {"ok": True, "message": "Invisible cursor kept"}

    def apply(self) -> dict:
        with self.lock:
            if not self.is_open or self.snapshots is None or self.draft_values is None:
                return {"ok": False, "message": "Cursor session is not open"}
            if self.invisible_token is not None:
                return {"ok": False, "message": "Confirm cursor visibility before applying"}

            current = self._take_snapshots()
            changed = [
                str(path) for path, content in self.snapshots.items()
                if current.get(path) != content
            ]
            if changed:
                return {
                    "ok": False,
                    "reason": "external_change",
                    "message": "Cursor configuration changed outside Cloud Center. Reload before applying.",
                    "paths": changed,
                }

            try:
                ok, message = self.activate_cursor()
                if not ok:
                    raise OSError(message)
                self.persist_cursor(copy.deepcopy(self.draft_values))
                self.persist_environment(self.draft_theme, self.draft_size)
            except Exception as exc:
                for path, content in current.items():
                    _restore(path, content)
                rollback_ok, rollback_message = self._restore_live()
                if rollback_ok:
                    self.draft_values = copy.deepcopy(self.baseline_values)
                    self.draft_theme = self.baseline_theme
                    self.draft_size = self.baseline_size
                message = f"Could not save Cursor settings: {exc}"
                if not rollback_ok:
                    message += f"; live rollback also failed: {rollback_message}"
                return {
                    "ok": False,
                    "message": message,
                    "values": copy.deepcopy(self.draft_values),
                    "theme": self.draft_theme,
                    "size": self.draft_size,
                    "dirty": self._dirty(),
                }

            self.snapshots = self._take_snapshots()
            self.baseline_values = copy.deepcopy(self.draft_values)
            self.baseline_theme = self.draft_theme
            self.baseline_size = self.draft_size
            return {"ok": True, "message": "Cursor settings saved"}

    def close(self) -> dict:
        with self.lock:
            if not self.is_open:
                return {"ok": True, "message": "Cursor session already closed"}
            ok, message = self._restore_live()
            if not ok:
                return {"ok": False, "message": message}
            self._clear_invisible_confirmation()
            self.snapshots = None
            self.baseline_values = None
            self.draft_values = None
            return {
                "ok": True,
                "message": "Cursor preview discarded",
            }

    def _dirty(self) -> bool:
        return bool(
            self.draft_values != self.baseline_values
            or self.draft_theme != self.baseline_theme
            or self.draft_size != self.baseline_size
        )

    def _restore_live(self) -> tuple[bool, str]:
        if self.baseline_values is None or self.draft_values is None:
            return True, "ok"
        failures: list[str] = []
        for key, baseline in self.baseline_values.items():
            if self.draft_values.get(key) == baseline:
                continue
            ok, message = self.apply_option(key, baseline)
            if not ok:
                failures.append(message)
        if (self.draft_theme, self.draft_size) != (self.baseline_theme, self.baseline_size):
            ok, message = self.apply_theme(self.baseline_theme, self.baseline_size)
            if not ok:
                failures.append(message)
        return (not failures, "; ".join(failures) or "ok")

    def _start_invisible_confirmation(self, previous: object) -> dict:
        self._clear_invisible_confirmation()
        self.invisible_previous = previous
        self.invisible_token = str(self.token_factory())
        token = self.invisible_token
        timeout = 15
        self.invisible_timer = self.timer_factory(
            timeout, lambda: self._timeout_invisible(token)
        )
        if hasattr(self.invisible_timer, "daemon"):
            self.invisible_timer.daemon = True
        self.invisible_timer.start()
        return {
            "confirmation_required": True,
            "token": token,
            "deadline": self.clock() + timeout,
        }

    def _timeout_invisible(self, token: str) -> None:
        with self.lock:
            if token != self.invisible_token or self.draft_values is None:
                return
            previous = self.invisible_previous
            ok, message = self.apply_option("invisible", previous)
            if ok:
                self.draft_values["invisible"] = previous
            self._clear_invisible_confirmation()
            self.event_sender({
                "event": "cursor_visibility",
                "state": "reverted" if ok else "error",
                "value": previous,
                "message": "Cursor visibility restored" if ok else message,
            })

    def _clear_invisible_confirmation(self) -> None:
        if self.invisible_timer is not None:
            self.invisible_timer.cancel()
        self.invisible_timer = None
        self.invisible_token = None


def _run_result(result: subprocess.CompletedProcess) -> tuple[bool, str]:
    message = ((result.stdout or "").strip() or (result.stderr or "").strip())
    lowered = message.lower()
    ok = result.returncode == 0 and not any(
        marker in lowered for marker in ("error", "failed", "invalid")
    )
    return ok, message or ("ok" if ok else f"command exited with status {result.returncode}")


def _fetch_values() -> dict[str, object]:
    values: dict[str, object] = {}
    for setting in CURSOR_SCHEMA:
        result = subprocess.run(
            ["hyprctl", "-j", "getoption", f"cursor:{setting['key']}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if result.returncode != 0:
            raise RuntimeError(
                (result.stderr or result.stdout or f"Could not read cursor:{setting['key']}").strip()
            )
        values[setting["key"]] = parse_live_value(setting, json.loads(result.stdout))
    return values


def _managed_environment() -> list[dict]:
    from lib import rules_startup_page as rules

    sections = rules._read_surface_sections(VARIABLES_PATH)
    return [
        {"name": variable.name, "value": variable.value}
        for variable in rules._parse_env_vars(sections["env_vars"])
    ]


def _fetch_appearance() -> tuple[str, int]:
    environment = {
        item["name"]: item["value"] for item in _managed_environment()
    }
    theme = environment.get("HYPRCURSOR_THEME") or os.environ.get(
        "HYPRCURSOR_THEME", DEFAULT_HYPRCURSOR_THEME
    )
    raw_size = environment.get("HYPRCURSOR_SIZE") or os.environ.get(
        "HYPRCURSOR_SIZE", str(DEFAULT_CURSOR_SIZE)
    )
    try:
        size = int(float(raw_size))
    except (TypeError, ValueError):
        size = 24
    return str(theme), size


def _fetch_themes() -> list[dict]:
    return discover_hyprcursor_themes(THEME_ROOTS)


def _fetch_monitors() -> list[str]:
    result = subprocess.run(
        ["hyprctl", "-j", "monitors"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "Could not list monitors").strip())
    return [
        str(item.get("name", ""))
        for item in json.loads(result.stdout)
        if item.get("name")
    ]


def _hypr_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return f"{value:g}"
    return str(value)


def _apply_option(key: str, value: object) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["hyprctl", "keyword", f"cursor:{key}", _hypr_value(value)],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except Exception as exc:
        return False, str(exc)
    return _run_result(result)


def _apply_theme(theme: str, size: int) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["hyprctl", "setcursor", theme, str(int(size))],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except Exception as exc:
        return False, str(exc)
    return _run_result(result)


def _persist_cursor(values: dict[str, object]) -> None:
    existing_path = CURSOR_PATH
    existing = (
        existing_path.read_text(encoding="utf-8")
        if existing_path.exists() else ""
    )
    _atomic_write(
        CURSOR_PATH,
        render_cursor_config(existing, values).encode("utf-8"),
    )


def _persist_environment(theme: str, size: int) -> None:
    from lib import rules_startup_page as rules

    existing = _managed_environment()
    merged = merge_cursor_environment(existing, theme, size)
    variables = [
        rules.EnvVar(name=item["name"], value=item["value"])
        for item in merged
    ]
    rules._write_conf([], [], [], variables, surfaces={"variables"})


SESSION = CursorSession(
    cursor_path=CURSOR_PATH,
    variables_path=VARIABLES_PATH,
    fetch_values=_fetch_values,
    fetch_appearance=_fetch_appearance,
    fetch_themes=_fetch_themes,
    fetch_monitors=_fetch_monitors,
    apply_option=_apply_option,
    apply_theme=_apply_theme,
    persist_cursor=_persist_cursor,
    persist_environment=_persist_environment,
    additional_paths=(
        WINDOWRULES_PATH,
        AUTOSTART_PATH,
    ),
    event_sender=protocol.send_event,
)


def open_cursor_session(params: dict) -> dict:
    return SESSION.open()


def preview_cursor_option(params: dict) -> dict:
    return SESSION.preview_option(
        str(params.get("key", "")), params.get("value")
    )


def preview_cursor_appearance(params: dict) -> dict:
    return SESSION.preview_appearance(
        str(params.get("theme", "")), int(params.get("size", 24))
    )


def keep_cursor_invisible(params: dict) -> dict:
    return SESSION.keep_invisible(str(params.get("token", "")))


def apply_cursor_settings(params: dict) -> dict:
    return SESSION.apply()


def close_cursor_session(params: dict) -> dict:
    return SESSION.close()


def shutdown() -> None:
    SESSION.close()


protocol.register("open_cursor_session", open_cursor_session)
protocol.register("preview_cursor_option", preview_cursor_option)
protocol.register("preview_cursor_appearance", preview_cursor_appearance)
protocol.register("keep_cursor_invisible", keep_cursor_invisible)
protocol.register("apply_cursor_settings", apply_cursor_settings)
protocol.register("close_cursor_session", close_cursor_session)
