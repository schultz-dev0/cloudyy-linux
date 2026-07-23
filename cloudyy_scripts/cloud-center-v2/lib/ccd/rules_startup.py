"""Transactional QML backend for the Rules & Startup page.

The legacy GTK page still owns the mature Lua parser/renderer and HCM
activation helpers.  This module adapts that data layer to plain JSON and
adds the page-session semantics required by the QML frontend: drafts do not
touch disk, Apply is atomic across every participating file, and external
edits are never overwritten silently.
"""
from __future__ import annotations

import copy
import json
import re
import subprocess
import threading
from pathlib import Path
from typing import Any

from lib import hyprlua_reader
from lib import rules_startup_page as rules
from lib.ccd import protocol


MATCH_MODES = [
    {"id": "exact", "label": "Exact"},
    {"id": "contains", "label": "Contains"},
    {"id": "starts_with", "label": "Starts with"},
    {"id": "ends_with", "label": "Ends with"},
    {"id": "regex", "label": "Regular expression"},
]

WINDOW_MATCHERS = [
    ("class", "Window class", "Application identifier", "pattern"),
    ("title", "Title", "Current window title", "pattern"),
    ("initial_class", "Initial class", "Class when the window first appeared", "pattern"),
    ("initial_title", "Initial title", "Title when the window first appeared", "pattern"),
    ("tag", "Tag", "A Hyprland window tag", "pattern"),
    ("xdg_tag", "XDG tag", "Application-provided XDG tag", "pattern"),
    ("workspace", "Workspace", "Workspace name or selector", "pattern"),
    ("content", "Content type", "none, photo, video, or game", "pattern"),
    ("xwayland", "XWayland", "Whether the window uses XWayland", "bool"),
    ("float", "Floating", "Whether the window is floating", "bool"),
    ("fullscreen", "Fullscreen", "Whether the window is fullscreen", "bool"),
    ("pin", "Pinned", "Whether the window is pinned", "bool"),
    ("focus", "Focused", "Whether the window has focus", "bool"),
    ("group", "Grouped", "Whether the window belongs to a group", "bool"),
    ("modal", "Modal", "Whether the window is modal", "bool"),
    ("fullscreen_state_client", "Client fullscreen state", "Client-requested fullscreen state", "number"),
    ("fullscreen_state_internal", "Internal fullscreen state", "Hyprland fullscreen state", "number"),
]

BOOLEAN_MATCHERS = {item[0] for item in WINDOW_MATCHERS if item[3] == "bool"}
NUMBER_MATCHERS = {item[0] for item in WINDOW_MATCHERS if item[3] == "number"}


def _field(key: str, label: str, group: str, field_type: str = "text",
           description: str = "", choices: list[str] | None = None) -> dict:
    result = {
        "key": key, "label": label, "group": group, "type": field_type,
        "description": description,
    }
    if choices:
        result["choices"] = choices
    return result


WINDOW_EFFECTS = [
    _field("float", "Float", "Common behavior", "bool", "Open as a floating window"),
    _field("tile", "Tile", "Common behavior", "bool", "Force the window into the tiled layout"),
    _field("center", "Center", "Common behavior", "bool", "Center a floating window"),
    _field("fullscreen", "Fullscreen", "Common behavior", "bool", "Open fullscreen"),
    _field("maximize", "Maximize", "Common behavior", "bool", "Open maximized"),
    _field("pin", "Pin", "Common behavior", "bool", "Show on every workspace"),
    _field("monitor", "Monitor", "Common behavior", "text", "Move to a monitor selector"),
    _field("workspace", "Workspace", "Common behavior", "text", "Move to a workspace selector"),
    _field("move", "Position", "Common behavior", "text", "Position, for example 20 40 or 50% 50%"),
    _field("size", "Size", "Common behavior", "text", "Size, for example 1200 800 or 60% 70%"),
    _field("opacity", "Opacity", "Appearance", "text", "Active/inactive/fullscreen opacity values"),
    _field("border_color", "Border color", "Appearance", "text", "Color or gradient"),
    _field("border_size", "Border size", "Appearance", "number", "Border width in pixels"),
    _field("rounding", "Rounding", "Appearance", "number", "Corner radius in pixels"),
    _field("rounding_power", "Rounding power", "Appearance", "number", "Corner curve power"),
    _field("animation", "Animation", "Appearance", "text", "Animation style"),
    _field("decorate", "Decorations", "Appearance", "bool", "Allow decorations"),
    _field("opaque", "Opaque", "Appearance", "bool", "Treat the window as fully opaque"),
    _field("no_anim", "Disable animation", "Appearance", "bool"),
    _field("no_blur", "Disable blur", "Appearance", "bool"),
    _field("no_dim", "Disable dimming", "Appearance", "bool"),
    _field("no_shadow", "Disable shadow", "Appearance", "bool"),
    _field("dim_around", "Dim around", "Appearance", "bool"),
    _field("xray", "X-ray", "Appearance", "bool"),
    _field("force_rgbx", "Force RGBX", "Appearance", "bool"),
    _field("nearest_neighbor", "Nearest-neighbor scaling", "Appearance", "bool"),
    _field("render_unfocused", "Render when unfocused", "Appearance", "bool"),
    _field("tonemap", "Tone mapping", "Appearance", "text"),
    _field("stay_focused", "Stay focused", "Focus & input", "bool"),
    _field("no_initial_focus", "No initial focus", "Focus & input", "bool"),
    _field("no_focus", "Never focus", "Focus & input", "bool"),
    _field("no_follow_mouse", "Ignore follow mouse", "Focus & input", "bool"),
    _field("focus_on_activate", "Focus on activation", "Focus & input", "bool"),
    _field("allows_input", "Allow input", "Focus & input", "bool"),
    _field("keep_aspect_ratio", "Keep aspect ratio", "Focus & input", "bool"),
    _field("confine_pointer", "Confine pointer", "Focus & input", "text"),
    _field("no_shortcuts_inhibit", "Ignore shortcut inhibition", "Focus & input", "bool"),
    _field("immediate", "Immediate rendering", "Performance & display", "bool"),
    _field("idle_inhibit", "Idle inhibition", "Performance & display", "choice", choices=["none", "always", "focus", "fullscreen"]),
    _field("no_vrr", "Disable VRR", "Performance & display", "bool"),
    _field("no_auto_hdr", "Disable auto HDR", "Performance & display", "bool"),
    _field("sync_fullscreen", "Synchronize fullscreen", "Performance & display", "bool"),
    _field("no_screen_share", "Exclude from screen sharing", "Privacy", "bool"),
    _field("persistent_size", "Remember size", "Layout & grouping", "bool"),
    _field("no_max_size", "Ignore maximum size", "Layout & grouping", "bool"),
    _field("pseudo", "Pseudotile", "Layout & grouping", "bool"),
    _field("group", "Group behavior", "Layout & grouping", "text"),
    _field("max_size", "Maximum size", "Layout & grouping", "text"),
    _field("min_size", "Minimum size", "Layout & grouping", "text"),
    _field("scrolling_width", "Scrolling width", "Layout & grouping", "number"),
    _field("scroll_mouse", "Mouse scrolling", "Layout & grouping", "text"),
    _field("scroll_touchpad", "Touchpad scrolling", "Layout & grouping", "text"),
    _field("fullscreen_state", "Fullscreen state", "Events & state", "text"),
    _field("suppress_event", "Suppress events", "Events & state", "text"),
    _field("content", "Content type", "Events & state", "choice", choices=["none", "photo", "video", "game"]),
    _field("no_close_for", "Delay closing", "Events & state", "number", "Minimum lifetime in milliseconds"),
    _field("tag", "Set tag", "Events & state", "text"),
]

LAYER_EFFECTS = [
    _field("blur", "Blur", "Common behavior", "bool"),
    _field("blur_popups", "Blur popups", "Common behavior", "bool"),
    _field("dim_around", "Dim around", "Common behavior", "bool"),
    _field("no_anim", "Disable animation", "Common behavior", "bool"),
    _field("animation", "Animation", "Common behavior", "text"),
    _field("ignore_alpha", "Ignore alpha below", "Advanced", "number"),
    _field("xray", "X-ray", "Advanced", "bool"),
    _field("order", "Render order", "Advanced", "number"),
    _field("above_lock", "Render above lock screen", "Advanced", "bool"),
    _field("no_screen_share", "Exclude from screen sharing", "Privacy", "bool"),
]

SCHEMA = {
    "matcher_modes": MATCH_MODES,
    "window_matchers": [
        {"key": key, "label": label, "description": description, "type": field_type}
        for key, label, description, field_type in WINDOW_MATCHERS
    ],
    "window_effects": WINDOW_EFFECTS,
    "layer_effects": LAYER_EFFECTS,
}


def encode_matcher(mode: str, value: str) -> str:
    """Convert a friendly match mode to Hyprland's regex string."""
    if mode == "regex":
        return value
    literal = re.escape(value)
    if mode == "contains":
        return f".*{literal}.*"
    if mode == "starts_with":
        return f"^{literal}.*"
    if mode == "ends_with":
        return f".*{literal}$"
    return f"^({literal})$"


def _literal_from_escaped(value: str) -> str | None:
    literal = re.sub(r"\\(.)", r"\1", value)
    return literal if re.escape(literal) == value else None


def decode_matcher(pattern: str) -> tuple[str, str]:
    """Recognise patterns generated by encode_matcher; preserve all others."""
    candidates: list[tuple[str, str]] = []
    if pattern.startswith("^(") and pattern.endswith(")$"):
        candidates.append(("exact", pattern[2:-2]))
    if pattern.startswith(".*") and pattern.endswith(".*"):
        candidates.append(("contains", pattern[2:-2]))
    if pattern.startswith("^") and pattern.endswith(".*"):
        candidates.append(("starts_with", pattern[1:-2]))
    if pattern.startswith(".*") and pattern.endswith("$"):
        candidates.append(("ends_with", pattern[2:-1]))
    for mode, body in candidates:
        literal = _literal_from_escaped(body)
        if literal is not None and encode_matcher(mode, literal) == pattern:
            return mode, literal
        # Older Cloud Center versions anchored plain identifier-like strings
        # without escaping punctuation such as hyphens.  They are still exact
        # matches and should not surprise users by opening in regex mode.
        if mode == "exact" and re.fullmatch(r"[A-Za-z0-9 _./:@-]+", body):
            return mode, body
    return "regex", pattern


def _window_to_json(rule: Any, *, origin: str | None = None) -> dict:
    matchers = []
    for key, pattern in rule.matchers:
        property_name = str(key).removeprefix("match:")
        if property_name in BOOLEAN_MATCHERS | NUMBER_MATCHERS:
            mode, value = "exact", str(pattern)
        else:
            mode, value = decode_matcher(str(pattern))
        matchers.append({
            "property": property_name,
            "mode": mode,
            "value": value,
        })
    result = {"name": rule.name, "matchers": matchers, "effects": dict(rule.effects)}
    if origin:
        result["origin"] = origin
    return result


def _layer_to_json(rule: Any, *, origin: str | None = None) -> dict:
    mode, namespace = decode_matcher(str(rule.namespace))
    result = {
        "name": rule.name,
        "namespace": namespace,
        "namespace_mode": mode,
        "effects": dict(rule.effects),
    }
    if origin:
        result["origin"] = origin
    return result


def _autostart_to_json(entry: Any, *, origin: str | None = None) -> dict:
    result = {"command": entry.command, "exec_once": bool(entry.exec_once)}
    if origin:
        result["origin"] = origin
    return result


def _env_to_json(entry: Any, *, origin: str | None = None) -> dict:
    result = {"name": entry.name, "value": entry.value}
    if origin:
        result["origin"] = origin
    return result


def _window_from_json(module: Any, item: dict) -> Any:
    matchers = []
    for matcher in item.get("matchers", []):
        property_name = str(matcher.get("property", ""))
        if not property_name:
            continue
        value = str(matcher.get("value", ""))
        rendered = value if property_name in BOOLEAN_MATCHERS | NUMBER_MATCHERS else encode_matcher(
            str(matcher.get("mode", "exact")), value,
        )
        matchers.append((f"match:{property_name}", rendered))
    effects = {str(key): str(value) for key, value in (item.get("effects") or {}).items()}
    return module.WindowRule(str(item.get("name", "")), matchers, effects)


def _layer_from_json(module: Any, item: dict) -> Any:
    namespace = encode_matcher(
        str(item.get("namespace_mode", "exact")), str(item.get("namespace", "")),
    )
    effects = {str(key): str(value) for key, value in (item.get("effects") or {}).items()}
    return module.LayerRule(str(item.get("name", "")), namespace, effects)


def _autostart_from_json(module: Any, item: dict) -> Any:
    return module.AutostartEntry(str(item.get("command", "")), bool(item.get("exec_once", True)))


def _env_from_json(module: Any, item: dict) -> Any:
    return module.EnvVar(str(item.get("name", "")), str(item.get("value", "")))


def _snapshot(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def _restore(path: Path, content: bytes | None) -> None:
    if content is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".rules-startup-rollback")
    temporary.write_bytes(content)
    temporary.replace(path)


def _default_reload() -> subprocess.CompletedProcess:
    return subprocess.run(
        ["hyprctl", "reload"], capture_output=True, text=True, timeout=8, check=False,
    )


class RulesStartupSession:
    def __init__(self, *, rules_module=rules, reload_runner=_default_reload) -> None:
        self.rules = rules_module
        self.reload_runner = reload_runner
        self.lock = threading.RLock()
        self._snapshots: dict[Path, bytes | None] | None = None

    @property
    def is_open(self) -> bool:
        return self._snapshots is not None

    def _paths(self) -> list[Path]:
        return [
            *(Path(pair[1]) for pair in self.rules.SURFACE_PATHS.values()),
            Path(self.rules.MAIN_LUA),
        ]

    def _take_snapshots(self) -> dict[Path, bytes | None]:
        return {path: _snapshot(path) for path in self._paths()}

    def _load(self) -> dict:
        user_texts = {
            surface: _snapshot(Path(path_pair[1]))
            for surface, path_pair in self.rules.SURFACE_PATHS.items()
        }
        decoded_user = {
            surface: (content or b"").decode("utf-8", errors="replace")
            for surface, content in user_texts.items()
        }
        sections = {
            surface: self.rules._parse_conf(text)
            for surface, text in decoded_user.items()
        }
        managed_windows = self.rules._parse_window_rules(sections["windowrules"]["window_rules"])
        managed_layers = self.rules._parse_layer_rules(sections["windowrules"]["layer_rules"])
        managed_autostart = self.rules._parse_autostart(sections["autostart"]["autostart"])
        managed_env = self.rules._parse_env_vars(sections["variables"]["env_vars"])

        source_texts = {
            surface: (Path(pair[0]).read_text(encoding="utf-8") if Path(pair[0]).exists() else "")
            for surface, pair in self.rules.SURFACE_PATHS.items()
        }
        distro_windows = self.rules._dataclass_window_rules(source_texts["windowrules"])
        distro_layers = self.rules._dataclass_layer_rules(source_texts["windowrules"])
        distro_autostart = self.rules._dataclass_autostart(source_texts["autostart"])
        distro_env = self.rules._dataclass_env_vars(source_texts["variables"])

        manual_windows = [
            self.rules.WindowRule(**item)
            for item in hyprlua_reader.parse_window_rules(decoded_user["windowrules"])
            if self.rules.WindowRule(**item) not in managed_windows
            and self.rules.WindowRule(**item) not in distro_windows
        ]
        manual_layers = [
            self.rules.LayerRule(**item) for item in hyprlua_reader.parse_layer_rules(decoded_user["windowrules"])
            if self.rules.LayerRule(**item) not in managed_layers
            and self.rules.LayerRule(**item) not in distro_layers
        ]
        manual_autostart = [
            self.rules.AutostartEntry(**item) for item in hyprlua_reader.parse_autostart(decoded_user["autostart"])
            if self.rules.AutostartEntry(**item) not in managed_autostart
            and self.rules.AutostartEntry(**item) not in distro_autostart
        ]
        manual_env = [
            self.rules.EnvVar(**item) for item in hyprlua_reader.parse_env_vars(decoded_user["variables"])
            if self.rules.EnvVar(**item) not in managed_env
            and self.rules.EnvVar(**item) not in distro_env
        ]

        return {
            "data": {
                "window_rules": [_window_to_json(item) for item in managed_windows],
                "layer_rules": [_layer_to_json(item) for item in managed_layers],
                "autostart": [_autostart_to_json(item) for item in managed_autostart],
                "env_vars": [_env_to_json(item) for item in managed_env],
            },
            "readonly": {
                "window_rules": ([_window_to_json(item, origin="distro") for item in distro_windows]
                                 + [_window_to_json(item, origin="user-manual") for item in manual_windows]),
                "layer_rules": ([_layer_to_json(item, origin="distro") for item in distro_layers]
                                + [_layer_to_json(item, origin="user-manual") for item in manual_layers]),
                "autostart": ([_autostart_to_json(item, origin="distro") for item in distro_autostart]
                              + [_autostart_to_json(item, origin="user-manual") for item in manual_autostart]),
                "env_vars": ([_env_to_json(item, origin="distro") for item in distro_env]
                             + [_env_to_json(item, origin="user-manual") for item in manual_env]),
            },
        }

    def open(self) -> dict:
        with self.lock:
            try:
                self.rules.migrate_legacy_conf()
                loaded = self._load()
                self._snapshots = self._take_snapshots()
                return {"ok": True, **loaded, "schema": copy.deepcopy(SCHEMA)}
            except Exception as exc:
                self._snapshots = None
                return {"ok": False, "message": f"Could not open Rules & Startup: {exc}"}

    def close(self) -> dict:
        with self.lock:
            self._snapshots = None
            return {"ok": True, "message": "Draft changes discarded"}

    def save(self, params: dict) -> dict:
        with self.lock:
            if self._snapshots is None:
                return {"ok": False, "message": "Rules & Startup session is not open"}
            allowed = {"windowrules", "autostart", "variables"}
            surfaces = {str(item) for item in params.get("dirty_surfaces", [])}
            if not surfaces:
                return {"ok": True, "message": "No changes to save"}
            if not surfaces <= allowed:
                return {"ok": False, "message": "Unknown Rules & Startup surface"}

            current = self._take_snapshots()
            changed = [str(path) for path, content in self._snapshots.items()
                       if current.get(path) != content]
            if changed:
                return {
                    "ok": False,
                    "reason": "external_change",
                    "message": "Configuration changed outside Cloud Center. Reload from disk before applying.",
                    "paths": changed,
                }

            window = [_window_from_json(self.rules, item) for item in params.get("window_rules", [])]
            layer = [_layer_from_json(self.rules, item) for item in params.get("layer_rules", [])]
            autostart = [_autostart_from_json(self.rules, item) for item in params.get("autostart", [])]
            env = [_env_from_json(self.rules, item) for item in params.get("env_vars", [])]

            try:
                self.rules._write_conf(window, layer, autostart, env, surfaces=surfaces)
                if "windowrules" in surfaces:
                    result = self.reload_runner()
                    if result.returncode != 0:
                        detail = (getattr(result, "stderr", "") or getattr(result, "stdout", "")
                                  or "hyprctl reload failed").strip()
                        raise RuntimeError(detail)
            except Exception as exc:
                for path, content in current.items():
                    _restore(path, content)
                if "windowrules" in surfaces:
                    try:
                        self.reload_runner()
                    except Exception:
                        pass
                return {"ok": False, "message": f"Could not apply Rules & Startup: {exc}"}

            self._snapshots = self._take_snapshots()
            loaded = self._load()
            restart_needed = bool(surfaces & {"autostart", "variables"})
            message = "Rules saved"
            if restart_needed:
                message += " — autostart and environment changes take effect next session"
            return {"ok": True, "message": message, **loaded}


SESSION = RulesStartupSession()


def open_rules_startup_session(params: dict) -> dict:
    return SESSION.open()


def close_rules_startup_session(params: dict) -> dict:
    return SESSION.close()


def save_rules_startup(params: dict) -> dict:
    return SESSION.save(params)


def _hyprctl_json(topic: str) -> Any:
    result = subprocess.run(
        ["hyprctl", topic, "-j"], capture_output=True, text=True, timeout=5, check=False,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or f"hyprctl {topic} failed").strip())
    return json.loads(result.stdout)


def list_rule_windows(params: dict) -> dict:
    clients = _hyprctl_json("clients")
    fields = ("address", "class", "title", "initialClass", "initialTitle", "xwayland",
              "floating", "fullscreen", "pinned", "workspace", "tags", "xdgTag", "contentType")
    return {"windows": [{key: client.get(key) for key in fields} for client in clients]}


def list_rule_layers(params: dict) -> dict:
    layers = []
    seen = set()
    for monitor, monitor_data in (_hyprctl_json("layers") or {}).items():
        for level, entries in (monitor_data.get("levels") or {}).items():
            for entry in entries:
                namespace = str(entry.get("namespace", ""))
                key = (monitor, namespace, str(entry.get("address", "")))
                if key in seen:
                    continue
                seen.add(key)
                layers.append({
                    "monitor": monitor, "level": level, "namespace": namespace,
                    "address": entry.get("address", ""), "pid": entry.get("pid", 0),
                })
    return {"layers": layers}


def _strip_exec_fields(command: str) -> str:
    return re.sub(r"(?:^|\s)%[fFuUdDnNickvm]", "", command).strip()


def list_autostart_apps(params: dict) -> dict:
    roots = [Path.home() / ".local/share/applications", Path("/usr/share/applications")]
    apps = []
    seen = set()
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.glob("*.desktop")):
            values: dict[str, str] = {}
            in_entry = False
            try:
                for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
                    if line.startswith("["):
                        in_entry = line == "[Desktop Entry]"
                        continue
                    if in_entry and "=" in line:
                        key, value = line.split("=", 1)
                        values.setdefault(key, value)
            except OSError:
                continue
            name = values.get("Name", "").strip()
            command = _strip_exec_fields(values.get("Exec", ""))
            if (not name or not command or values.get("Type", "Application") != "Application"
                    or values.get("NoDisplay", "").lower() == "true" or name in seen):
                continue
            seen.add(name)
            apps.append({"name": name, "command": command, "icon": values.get("Icon", "")})
    apps.sort(key=lambda item: item["name"].casefold())
    return {"apps": apps}


def preview_rule(params: dict) -> dict:
    kind = str(params.get("kind", "window"))
    item = params.get("rule") or {}
    if kind == "layer":
        rendered = rules._render_layer_rules_lua([_layer_from_json(rules, item)])
    else:
        rendered = rules._render_window_rules_lua([_window_from_json(rules, item)])
    return {"lua": "\n".join(rendered).rstrip()}


def shutdown() -> None:
    SESSION.close()


protocol.register("open_rules_startup_session", open_rules_startup_session)
protocol.register("save_rules_startup", save_rules_startup)
protocol.register("close_rules_startup_session", close_rules_startup_session)
protocol.register("list_rule_windows", list_rule_windows)
protocol.register("list_rule_layers", list_rule_layers)
protocol.register("list_autostart_apps", list_autostart_apps)
protocol.register("preview_rule", preview_rule)
