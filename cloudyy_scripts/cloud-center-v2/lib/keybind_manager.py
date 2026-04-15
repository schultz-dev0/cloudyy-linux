"""Cloud Center keybind manager — categorized dialog-based editor.

Mirrors the config manager pattern:
- Writes to ~/.config/hypr/hyprland-keybinds-cloud-center.conf
- Auto-injects source line into hyprland.conf if missing (atomic write)
- Dialog-based add/edit with dispatcher categories
- Locked original binds shown as read-only reference
"""
from __future__ import annotations

import logging
import os
import re
import tempfile
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from gi.repository import Adw, Gdk, GLib, Gtk, Pango

import lib.hcm as hcm

log = logging.getLogger(__name__)


HYPR_DIR = Path.home() / ".config" / "hypr"
HYPRLAND_CONF = HYPR_DIR / "hyprland.conf"
KEYBINDS_CONF = hcm.USER_DIR / "user_bindings.conf"
_KEYBINDS_TILDE = "~/.config/hypr/user-configs/user_bindings.conf"
_SOURCE_BINDINGS = hcm.SOURCE_DIR / "bindings.conf"

# Marker lines that delimit the Cloud Center-managed section within user_bindings.conf
_CC_BEGIN = "# --- Cloud Center Additions (managed by Cloud Center) ---"
_CC_END   = "# --- End Cloud Center Additions ---"


# ── Dispatcher categories (HyprMod-inspired) ──────────────────────────────


DISPATCHER_CATEGORIES = [
    {
        "id": "workspace",
        "label": "Workspace Navigation",
        "icon": "shell-overview-symbolic",
    },
    {
        "id": "window",
        "label": "Window Management",
        "icon": "overlapping-windows-symbolic",
    },
    {
        "id": "app",
        "label": "Launch Application",
        "icon": "system-run-symbolic",
    },
    {
        "id": "other",
        "label": "Other / Special",
        "icon": "terminal-symbolic",
    },
]

# Full dispatcher lists per category (Hyprland reference)
DISPATCHER_MAP: dict[str, list[str]] = {
    "workspace": [
        "workspace",
        "movetoworkspace",
        "movetoworkspacesilent",
        "focusworkspace",
        "swapactiveworkspaces",
        "movecurrentworkspacetomonitor",
        "renameworkspace",
        "togglespecialworkspace",
        "movetoworkspace special",
    ],
    "window": [
        "killactive",
        "closewindow",
        "togglefloating",
        "fullscreen",
        "fakefullscreen",
        "pseudo",
        "togglesplit",
        "movefocus",
        "movewindow",
        "swapwindow",
        "centerwindow",
        "resizeactive",
        "moveactive",
        "cyclenext",
        "focuswindow",
        "pin",
        "alterzorder",
        "setfloating",
        "settiled",
        "focusmonitor",
        "movewindowpixel",
        "resizewindowpixel",
    ],
    "app": [
        "exec",
        "execr",
        "pass",
        "sendshortcut",
    ],
    "other": [
        "exit",
        "forcerendererreload",
        "focusmonitor",
        "splitratio",
        "layoutmsg",
        "submap",
        "dpms",
        "hyprexpo:expo",
        "global",
        "bringactivetotop",
        "lockactivegroup",
        "moveoutofgroup",
        "moveintogroup",
        "togglegroup",
        "changegroupactive",
    ],
}


def _categorize_dispatcher(dispatcher: str) -> str:
    """Categorize a dispatcher by name."""
    parts = dispatcher.lower().split()
    if not parts:
        return "other"
    d = parts[0]
    for cat_id, dispatchers in DISPATCHER_MAP.items():
        if any(d == entry.lower().split()[0] for entry in dispatchers):
            return cat_id
    # Fallback heuristics
    if "workspace" in d or "moveto" in d:
        return "workspace"
    if any(x in d for x in ("window", "kill", "floating", "fullscreen", "focus", "move", "swap")):
        return "window"
    if d in ("exec", "execr", "pass"):
        return "app"
    return "other"


# ── Data Model ────────────────────────────────────────────────────────────────


@dataclass
class KeybindEntry:
    mods: str
    key: str
    combo: str
    bind_type: str
    dispatcher: str
    args: str
    raw_line: str
    owned: bool
    source_name: str = ""
    line_no: int = 0


# ── Variable resolution ───────────────────────────────────────────────────────

# bind types that carry an extra description field before the dispatcher
_BINDD_TYPES = frozenset({"bindd", "bindde", "binddl", "binddel", "binddm"})

# Modifier aliases Hyprland accepts — normalise to uppercase
_MOD_ALIASES: dict[str, str] = {
    "super": "SUPER", "mod4": "SUPER", "win": "SUPER",
    "ctrl": "CTRL", "control": "CTRL",
    "alt": "ALT", "mod1": "ALT",
    "shift": "SHIFT",
    "mod2": "MOD2", "mod3": "MOD3", "mod5": "MOD5",
}


def _load_variables(extra_files: list[Path] | None = None) -> dict[str, str]:
    """Build a $variable→value map from variables.conf and scanned files."""
    variables: dict[str, str] = {}

    def _parse_vars_from(path: Path) -> None:
        try:
            for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = raw.split("#", 1)[0].strip()
                if not line or "=" not in line:
                    continue
                lhs, rhs = line.split("=", 1)
                name = lhs.strip()
                if name.startswith("$"):
                    variables[name] = rhs.strip()
        except OSError:
            pass

    # Load from the variables source file (and its user override)
    for cf in hcm.scan_config_files():
        if "variable" not in cf.filename.lower():
            continue
        user_name = cf.filename if cf.filename.startswith("user_") else f"user_{cf.filename}"
        user_path = hcm.USER_DIR / user_name
        _parse_vars_from(user_path if user_path.exists() else cf.path)

    # Also parse any extra files passed in (e.g. user_bindings.conf may define $scripts)
    for path in (extra_files or []):
        _parse_vars_from(path)

    return variables


def _expand_vars(text: str, variables: dict[str, str]) -> str:
    """Replace $variable references — longest name first to avoid partial matches."""
    for name, value in sorted(variables.items(), key=lambda kv: -len(kv[0])):
        text = text.replace(name, value)
    return text


def _normalise_mods(mods: str) -> str:
    """Normalise modifier string: resolve aliases, uppercase, deduplicate."""
    # Hyprland allows both spaces and | as mod separators
    separators = mods.replace("|", " ")
    parts = [p.strip() for p in separators.split() if p.strip()]
    seen: list[str] = []
    for p in parts:
        norm = _MOD_ALIASES.get(p.lower(), p.upper())
        if norm not in seen:
            seen.append(norm)
    return " ".join(seen)


# ── Parsing and I/O ───────────────────────────────────────────────────────────


def _strip_inline_comment(line: str) -> str:
    """Strip trailing # comments."""
    return line.split("#", 1)[0].rstrip()


def _parse_bind_line(
    line: str,
    variables: dict[str, str] | None = None,
) -> tuple[str, str, str, str, str, str] | None:
    """Return (mods, key, combo, bind_type, dispatcher, args) or None.

    Handles:
    - Normal:  bind[type] = mods, key, dispatcher, [args...]
    - bindd:   bindd[type] = mods, key, description, dispatcher, [args...]
    - Variable expansion when ``variables`` is supplied.
    """
    clean = _strip_inline_comment(line).strip()
    if not clean or "=" not in clean:
        return None

    lhs, rhs = clean.split("=", 1)
    bind_type = lhs.strip()
    if not bind_type.startswith("bind"):
        return None

    # Expand variables if provided
    if variables:
        rhs = _expand_vars(rhs, variables)

    parts = [p.strip() for p in rhs.split(",")]

    # bindd variants have an extra description field: mods, key, desc, disp, [args]
    if bind_type in _BINDD_TYPES:
        if len(parts) < 4:
            return None
        mods, key, _desc, dispatcher = parts[0], parts[1], parts[2], parts[3]
        args = ", ".join(parts[4:]).strip()
    else:
        if len(parts) < 3:
            return None
        mods, key, dispatcher = parts[0], parts[1], parts[2]
        args = ", ".join(parts[3:]).strip()

    # Normalise mods (resolve aliases, uppercase, deduplicate)
    mods = _normalise_mods(mods)

    if mods and mods.upper() != "NONE":
        combo = f"{mods} + {key.upper()}"
    else:
        combo = key.upper()

    return mods, key.upper(), combo, bind_type, dispatcher, args


def _entry_to_line(entry: KeybindEntry) -> str:
    """Convert entry to bind line."""
    # Hyprland uses empty string for no modifiers, not "NONE"
    mods = "" if entry.mods.upper() in ("", "NONE") else entry.mods
    rhs = f"{mods}, {entry.key}, {entry.dispatcher}"
    if entry.args:
        rhs += f", {entry.args}"
    return f"{entry.bind_type} = {rhs}"


def _scan_file(
    path: Path,
    *,
    owned: bool = False,
    variables: dict[str, str] | None = None,
) -> list[KeybindEntry]:
    """Scan a config file for bind lines, expanding variables if provided."""
    if not path.exists():
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []

    out: list[KeybindEntry] = []
    for idx, raw in enumerate(lines, start=1):
        parsed = _parse_bind_line(raw, variables=variables)
        if parsed is None:
            continue
        mods, key, combo, bind_type, dispatcher, args = parsed
        out.append(
            KeybindEntry(
                mods=mods,
                key=key,
                combo=combo,
                bind_type=bind_type,
                dispatcher=dispatcher,
                args=args,
                raw_line=raw.strip(),
                owned=owned,
                source_name=path.name,
                line_no=idx,
            )
        )
    return out


def _ensure_keybinds_conf() -> None:
    """Ensure user_bindings.conf exists and hyprland.conf sources it.

    If source/bindings.conf exists, uses hcm.switch_to_user_copy() which:
      - Copies source/bindings.conf → user-configs/user_bindings.conf
      - Replaces the 'source = .../source/bindings.conf' line in hyprland.conf
        with 'source = ~/.config/hypr/user-configs/user_bindings.conf'
    Then appends the CC marker section if not yet present.
    If no source file, creates a minimal stub and appends a source line.
    """
    if KEYBINDS_CONF.exists():
        # Ensure the marker section exists even in pre-existing files
        text = KEYBINDS_CONF.read_text(encoding="utf-8")
        if _CC_BEGIN not in text:
            with open(KEYBINDS_CONF, "a", encoding="utf-8") as f:
                f.write(f"\n{_CC_BEGIN}\n{_CC_END}\n")
        # Still make sure it is sourced in hyprland.conf
        hcm.ensure_user_config_sourced(KEYBINDS_CONF)
        return

    hcm.USER_DIR.mkdir(parents=True, exist_ok=True)

    if _SOURCE_BINDINGS.exists():
        # Use hcm to copy source file and rewrite the source line atomically
        fake_cf = hcm.ConfigFile(
            filename=_SOURCE_BINDINGS.name,
            path=_SOURCE_BINDINGS,
            description="Hyprland keybindings",
            status=hcm.FileStatus.DISTRO,
        )
        hcm.switch_to_user_copy(fake_cf)
        log.info("Created user_bindings.conf from source/bindings.conf")
    else:
        # No source file — create a minimal stub
        KEYBINDS_CONF.write_text(
            "# Cloud Center — user keybind additions\n"
            "# Original keybinds remain in your hyprland source configs.\n",
            encoding="utf-8",
        )
        hcm.ensure_user_config_sourced(KEYBINDS_CONF)
        log.info("Created stub %s (no source/bindings.conf found)", KEYBINDS_CONF)

    # Append the CC marker section
    with open(KEYBINDS_CONF, "a", encoding="utf-8") as f:
        f.write(f"\n{_CC_BEGIN}\n{_CC_END}\n")


def _ensure_source_line() -> None:
    """Compatibility shim — delegate to _ensure_keybinds_conf."""
    _ensure_keybinds_conf()


def _read_cc_section(text: str) -> str:
    """Extract the text between the CC marker lines (exclusive of markers)."""
    m = re.search(
        re.escape(_CC_BEGIN) + r"\n(.*?)" + re.escape(_CC_END),
        text,
        re.DOTALL,
    )
    return m.group(1) if m else ""


def scan_keybinds() -> list[KeybindEntry]:
    """Load keybinds with variable expansion and proper bindd handling.

    Sources:
    - Lines AFTER _CC_BEGIN marker in user_bindings.conf  → owned (CC-managed)
    - Lines BEFORE _CC_BEGIN marker in user_bindings.conf → locked (distro base copy)
    - Other source/ config files (not bindings.conf)      → locked
    """
    _ensure_keybinds_conf()

    # Build variable map; pass all user conf files so $vars resolve.
    extra_var_files: list[Path] = []
    for cf in hcm.scan_config_files():
        user_name = cf.filename if cf.filename.startswith("user_") else f"user_{cf.filename}"
        user_path = hcm.USER_DIR / user_name
        extra_var_files.append(user_path if user_path.exists() else cf.path)
    variables = _load_variables(extra_var_files)

    keybinds_resolved = KEYBINDS_CONF.resolve() if KEYBINDS_CONF.exists() else KEYBINDS_CONF
    seen_paths: set[Path] = {keybinds_resolved}

    owned: list[KeybindEntry] = []
    locked_from_base: list[KeybindEntry] = []

    if KEYBINDS_CONF.exists():
        full_text = KEYBINDS_CONF.read_text(encoding="utf-8", errors="replace")
        cc_section = _read_cc_section(full_text)

        # Owned = bind lines inside the CC section
        for raw in cc_section.splitlines():
            parsed = _parse_bind_line(raw, variables=variables)
            if parsed is None:
                continue
            mods, key, combo, bind_type, dispatcher, args = parsed
            owned.append(KeybindEntry(
                mods=mods, key=key, combo=combo, bind_type=bind_type,
                dispatcher=dispatcher, args=args, raw_line=raw.strip(),
                owned=True, source_name=KEYBINDS_CONF.name,
            ))

        # Locked = bind lines before the CC BEGIN marker (distro base)
        before_marker = full_text.split(_CC_BEGIN)[0]
        for raw in before_marker.splitlines():
            parsed = _parse_bind_line(raw, variables=variables)
            if parsed is None:
                continue
            mods, key, combo, bind_type, dispatcher, args = parsed
            locked_from_base.append(KeybindEntry(
                mods=mods, key=key, combo=combo, bind_type=bind_type,
                dispatcher=dispatcher, args=args, raw_line=raw.strip(),
                owned=False, source_name=KEYBINDS_CONF.name,
            ))

    owned_combos = {e.combo for e in owned}
    locked: list[KeybindEntry] = list(locked_from_base)
    locked_combos = {e.combo for e in locked_from_base}

    # Additional source/ config files (excluding user_bindings.conf itself)
    for cf in hcm.scan_config_files():
        if cf.filename in ("bindings.conf", "user_bindings.conf"):
            continue
        user_name = cf.filename if cf.filename.startswith("user_") else f"user_{cf.filename}"
        user_path = hcm.USER_DIR / user_name
        parse_path = user_path if user_path.exists() else cf.path
        try:
            resolved = parse_path.resolve()
        except OSError:
            resolved = parse_path
        if resolved in seen_paths:
            continue
        seen_paths.add(resolved)
        for e in _scan_file(parse_path, owned=False, variables=variables):
            if e.combo not in owned_combos and e.combo not in locked_combos:
                locked.append(e)

    merged = owned + locked
    merged.sort(key=lambda e: (not e.owned, e.combo.lower(), e.dispatcher.lower()))
    return merged


def _write_cc_section(lines_to_write: list[str]) -> None:
    """Replace the CC-managed section in user_bindings.conf with new lines."""
    _ensure_keybinds_conf()
    text = KEYBINDS_CONF.read_text(encoding="utf-8", errors="replace")
    cc_content = "\n".join(lines_to_write)
    if cc_content:
        cc_content += "\n"
    if _CC_BEGIN in text:
        pattern = re.escape(_CC_BEGIN) + r".*?" + re.escape(_CC_END)
        replacement = f"{_CC_BEGIN}\n{cc_content}{_CC_END}"
        new_text = re.sub(pattern, replacement, text, flags=re.DOTALL)
    else:
        new_text = text.rstrip() + f"\n{_CC_BEGIN}\n{cc_content}{_CC_END}\n"
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(KEYBINDS_CONF.parent))
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.write(new_text)
        f.flush()
        os.fsync(f.fileno())
    Path(tmp_path).replace(KEYBINDS_CONF)


def _get_cc_lines() -> list[str]:
    """Return the bind lines currently in the CC-managed section."""
    if not KEYBINDS_CONF.exists():
        return []
    text = KEYBINDS_CONF.read_text(encoding="utf-8", errors="replace")
    cc_text = _read_cc_section(text)
    return [ln for ln in cc_text.splitlines() if ln.strip()]


def add_keybind(entry: KeybindEntry) -> tuple[bool, str]:
    """Append a new keybind to the CC section of user_bindings.conf."""
    _ensure_keybinds_conf()
    lines = _get_cc_lines()
    lines.append(_entry_to_line(entry))
    _write_cc_section(lines)
    return True, "keybind added"


def remove_keybind(entry: KeybindEntry) -> tuple[bool, str]:
    """Remove a keybind from the CC section of user_bindings.conf."""
    if not KEYBINDS_CONF.exists():
        return False, "keybind config not found"

    combo_line = _entry_to_line(entry).strip()
    lines = _get_cc_lines()
    out = [ln for ln in lines if ln.strip() != combo_line]

    if len(out) == len(lines):
        return False, "keybind not found"

    _write_cc_section(out)
    return True, "keybind removed"


def update_keybind(old_entry: KeybindEntry, new_entry: KeybindEntry) -> tuple[bool, str]:
    """Replace an existing keybind line in the CC section of user_bindings.conf."""
    if not KEYBINDS_CONF.exists():
        return False, "keybind config not found"

    old_line = _entry_to_line(old_entry).strip()
    new_line = _entry_to_line(new_entry)
    lines = _get_cc_lines()

    replaced = False
    out: list[str] = []
    for line in lines:
        if not replaced and line.strip() == old_line:
            out.append(new_line)
            replaced = True
        else:
            out.append(line)

    if not replaced:
        return False, "keybind not found"

    _write_cc_section(out)
    return True, "keybind updated"


# ── Edit Dialog (placeholder for HyprMod-style UI) ────────────────────────────


class KeybindEditDialog(Adw.Dialog):
    """HyprMod-inspired keybind edit dialog with categorized actions."""

    def __init__(
        self,
        window: Gtk.Window,
        toast_overlay: Adw.ToastOverlay,
        entry: KeybindEntry | None = None,
        on_apply=None,
    ) -> None:
        super().__init__()
        self._window = window
        self._toast_ov = toast_overlay
        self._entry = entry or KeybindEntry(
            mods="",
            key="",
            combo="",
            bind_type="bind",
            dispatcher="",
            args="",
            raw_line="",
            owned=True,
        )
        self._on_apply = on_apply
        self._capturing = False
        self._key_controller: Gtk.EventControllerKey | None = None
        self._key_controller_local: Gtk.EventControllerKey | None = None

        self.set_title("Add Keybind" if entry is None else "Edit Keybind")
        self.set_content_width(500)
        self.set_content_height(600)

        self._build_ui()

    def _build_ui(self) -> None:
        toolbar = Adw.ToolbarView()

        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", self._on_cancel_clicked)
        header.pack_start(cancel_btn)

        self._apply_btn = Gtk.Button(label="Apply")
        self._apply_btn.add_css_class("suggested-action")
        self._apply_btn.connect("clicked", self._on_apply_clicked)
        header.pack_end(self._apply_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        content.set_margin_top(16)
        content.set_margin_bottom(16)
        content.set_margin_start(16)
        content.set_margin_end(16)

        # Key section
        key_group = Adw.PreferencesGroup(title="Key Combination")
        self._capture_label = Gtk.Label(
            label=self._entry.combo or "Press Record to capture…"
        )
        self._capture_label.add_css_class("dim-label")
        capture_row = Adw.ActionRow(title="Shortcut")
        capture_row.add_suffix(self._capture_label)
        self._capture_btn = Gtk.Button(label="Record")
        self._capture_btn.add_css_class("suggested-action")
        self._capture_btn.connect("clicked", self._on_capture_start)
        capture_row.add_suffix(self._capture_btn)
        key_group.add(capture_row)
        content.append(key_group)

        # Action section
        action_group = Adw.PreferencesGroup(title="Action")
        self._category_combo = Adw.ComboRow(title="Category")
        cat_labels = [c["label"] for c in DISPATCHER_CATEGORIES]
        self._category_combo.set_model(Gtk.StringList.new(cat_labels))
        self._category_combo.connect("notify::selected", self._on_category_changed)
        action_group.add(self._category_combo)

        self._dispatcher_combo = Adw.ComboRow(title="Dispatcher")
        self._dispatcher_combo.connect("notify::selected", self._on_dispatcher_changed)
        action_group.add(self._dispatcher_combo)

        content.append(action_group)

        # Arguments section
        self._args_entry = Adw.EntryRow(title="Arguments")
        self._args_entry.set_text(self._entry.args or "")
        content.append(self._args_entry)

        # Bind type section
        advanced_group = Adw.PreferencesGroup(title="Advanced")
        self._type_combo = Adw.ComboRow(title="Bind Type")
        self._type_combo.set_model(
            Gtk.StringList.new(["Normal", "Repeat", "Locked", "Release", "Non-consuming"])
        )
        self._type_combo.set_selected(0)
        advanced_group.add(self._type_combo)
        content.append(advanced_group)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(content)
        toolbar.set_content(scroll)
        self.set_child(toolbar)

        # Pre-select bind type for existing entry
        bind_map = {"bind": 0, "binde": 1, "bindl": 2, "bindr": 3, "bindn": 4}
        self._type_combo.set_selected(bind_map.get(self._entry.bind_type, 0))

        # Pre-select category/dispatcher for existing entry
        if self._entry.dispatcher:
            cat = _categorize_dispatcher(self._entry.dispatcher)
            for i, c in enumerate(DISPATCHER_CATEGORIES):
                if c["id"] == cat:
                    self._category_combo.set_selected(i)
                    break
        self._populate_dispatchers()

    def _populate_dispatchers(self, keep_selected: str = "") -> None:
        """Populate dispatcher dropdown for selected category."""
        idx = self._category_combo.get_selected()
        if idx >= len(DISPATCHER_CATEGORIES):
            return
        cat_id = DISPATCHER_CATEGORIES[idx]["id"]
        dispatchers = DISPATCHER_MAP.get(cat_id, ["exec"])
        self._dispatcher_combo.set_model(Gtk.StringList.new(dispatchers))

        # Pre-select the matching dispatcher if editing
        target = keep_selected or self._entry.dispatcher
        if target:
            for i, d in enumerate(dispatchers):
                if d.lower().split()[0] == target.lower().split()[0]:
                    self._dispatcher_combo.set_selected(i)
                    return
        self._dispatcher_combo.set_selected(0)

    def _on_category_changed(self, *_) -> None:
        self._populate_dispatchers()

    def _on_dispatcher_changed(self, *_) -> None:
        pass

    def _get_selected_dispatcher(self) -> str:
        idx = self._dispatcher_combo.get_selected()
        model = self._dispatcher_combo.get_model()
        if model and idx < model.get_n_items():
            item = model.get_item(idx)
            return item.get_string() if item else ""
        return ""

    def _on_cancel_clicked(self, _btn: Gtk.Button) -> None:
        self._capture_stop()
        self.close()

    def _on_capture_start(self, _btn: Gtk.Button) -> None:
        """Start interactive key capture — attach controller to ROOT WINDOW at CAPTURE phase.

        Adw.Dialog lives inside the parent window's widget tree, so adding the
        controller to get_root() (the Gtk.Window) is the only reliable way to
        intercept all key events before any child widget consumes them.
        """
        if self._capturing:
            self._capture_stop()
            return
        self._capturing = True
        self._capture_btn.set_label("Press a key…")
        self._capture_btn.add_css_class("destructive-action")
        self._capture_btn.remove_css_class("suggested-action")
        self._capture_label.set_label("Waiting for key…")

        # Ensure the dialog itself can receive keyboard focus while recording.
        try:
            self.grab_focus()
        except Exception:
            pass

        # Attach one controller to the dialog and one to the root window.
        # Different compositors/theme stacks may route events differently for
        # Adw.Dialog; listening on both avoids dead zones.
        self._key_controller_local = Gtk.EventControllerKey.new()
        self._key_controller_local.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        self._key_controller_local.connect("key-pressed", self._on_key_captured)
        self.add_controller(self._key_controller_local)

        root = self.get_root()
        self._key_root: Gtk.Widget = root if root is not None else self
        self._key_controller = Gtk.EventControllerKey.new()
        self._key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        self._key_controller.connect("key-pressed", self._on_key_captured)
        self._key_root.add_controller(self._key_controller)

    def _capture_stop(self) -> None:
        """Stop key capture and remove the controller from the root window."""
        self._capturing = False
        self._capture_btn.set_label("Record")
        self._capture_btn.remove_css_class("destructive-action")
        self._capture_btn.add_css_class("suggested-action")
        if self._key_controller_local is not None:
            self.remove_controller(self._key_controller_local)
            self._key_controller_local = None
        if self._key_controller is not None:
            target = getattr(self, "_key_root", self)
            target.remove_controller(self._key_controller)
            self._key_controller = None
            self._key_root = None

    # Modifier-only keys to ignore during capture
    _MOD_KEYS = frozenset({
        "Control_L", "Control_R",
        "Alt_L", "Alt_R", "Meta_L", "Meta_R",
        "Shift_L", "Shift_R",
        "Super_L", "Super_R", "Hyper_L", "Hyper_R",
        "Caps_Lock", "Num_Lock", "Scroll_Lock",
    })

    def _on_key_captured(self, _ctrl, keyval: int, _keycode: int, state) -> bool:
        """Handle key capture at the dialog level."""
        key_name = Gdk.keyval_name(keyval)
        if not key_name:
            return True

        if key_name == "Escape":
            self._capture_label.set_label(self._entry.combo or "Press Record to capture…")
            self._capture_stop()
            return True

        # Skip standalone modifier presses
        if key_name in self._MOD_KEYS:
            return True

        mods: list[str] = []
        if state & Gdk.ModifierType.SUPER_MASK:
            mods.append("SUPER")
        if state & Gdk.ModifierType.CONTROL_MASK:
            mods.append("CTRL")
        if state & Gdk.ModifierType.ALT_MASK:
            mods.append("ALT")
        if state & Gdk.ModifierType.SHIFT_MASK:
            mods.append("SHIFT")

        self._entry.mods = " ".join(mods) if mods else "NONE"
        self._entry.key = key_name.upper()
        if mods:
            self._entry.combo = " + ".join(mods + [self._entry.key])
        else:
            self._entry.combo = self._entry.key

        self._capture_label.set_label(self._entry.combo)
        self._capture_stop()
        return True

    def _on_apply_clicked(self, _btn: Gtk.Button) -> None:
        """Apply the keybind entry."""
        self._capture_stop()  # ensure no dangling controller on root window

        if not self._entry.key:
            return  # no key captured yet

        bind_types = ["bind", "binde", "bindl", "bindr", "bindn"]
        type_idx = self._type_combo.get_selected()
        if type_idx < len(bind_types):
            self._entry.bind_type = bind_types[type_idx]

        dispatcher = self._get_selected_dispatcher()
        if dispatcher:
            self._entry.dispatcher = dispatcher

        if not self._entry.dispatcher:
            return  # no dispatcher selected — don't write a malformed entry

        self._entry.args = self._args_entry.get_text().strip()
        self._entry.raw_line = _entry_to_line(self._entry)

        if self._on_apply:
            self._on_apply(self._entry)
        self.close()


# ── Category metadata (display order, labels, icons) ─────────────────────────

CATEGORY_ORDER: list[str] = ["workspace", "window", "app", "other"]

CATEGORY_META: dict[str, tuple[str, str]] = {
    "workspace": ("Workspace Navigation", "shell-overview-symbolic"),
    "window":    ("Window Management",    "overlapping-windows-symbolic"),
    "app":       ("Applications",         "system-run-symbolic"),
    "other":     ("Other / Special",      "terminal-symbolic"),
}


# ── Main Page ─────────────────────────────────────────────────────────────────


class KeybindManagerPage(Gtk.Box):
    """Dialog-based keybind manager with lock/unlock workflow."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov = toast_overlay
        self._entries: list[KeybindEntry] = []
        self._filtered: list[KeybindEntry] = []

        self._build_ui()
        self.refresh()

    def _build_ui(self) -> None:
        # Single full-width panel — no right detail pane
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel.set_hexpand(True)

        # ── Toolbar ──
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        header.set_margin_start(14)
        header.set_margin_end(10)
        header.set_margin_top(10)
        header.set_margin_bottom(6)

        title = Gtk.Label(label="Keybinds")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._count = Gtk.Label(label="")
        self._count.add_css_class("dim-label")
        self._count.add_css_class("caption")

        self._add_btn = Gtk.Button(icon_name="list-add-symbolic")
        self._add_btn.add_css_class("flat")
        self._add_btn.add_css_class("keybind-white-btn")
        self._add_btn.set_tooltip_text("Add keybind")
        self._add_btn.connect("clicked", self._on_add_clicked)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.add_css_class("keybind-white-btn")
        refresh_btn.set_tooltip_text("Rescan keybinds")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        self._reload_btn = Gtk.Button(icon_name="system-reboot-symbolic")
        self._reload_btn.add_css_class("flat")
        self._reload_btn.add_css_class("keybind-white-btn")
        self._reload_btn.set_tooltip_text("Reload Hyprland")
        self._reload_btn.connect("clicked", self._on_reload_clicked)

        header.append(title)
        header.append(self._count)
        header.append(self._add_btn)
        header.append(refresh_btn)
        header.append(self._reload_btn)
        panel.append(header)

        # ── Search ──
        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search keybinds…")
        self._search.set_margin_start(12)
        self._search.set_margin_end(12)
        self._search.set_margin_bottom(6)
        self._search.connect("search-changed", self._on_search_changed)
        panel.append(self._search)

        hint = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hint.set_margin_start(12)
        hint.set_margin_end(12)
        hint.set_margin_bottom(8)
        hint_icon = Gtk.Image.new_from_icon_name("changes-prevent-symbolic")
        hint_icon.add_css_class("dim-label")
        hint_label = Gtk.Label(
            label="Locked keybinds come from your hyprland.conf. Click edit to override them."
        )
        hint_label.add_css_class("dim-label")
        hint_label.add_css_class("caption")
        hint_label.set_xalign(0)
        hint_label.set_wrap(True)
        hint.append(hint_icon)
        hint.append(hint_label)
        panel.append(hint)
        panel.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # ── List ──
        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.add_css_class("navigation-sidebar")

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        scroll.set_child(self._list)
        panel.append(scroll)

        self.append(panel)

    def refresh(self) -> None:
        threading.Thread(target=self._do_refresh, daemon=True).start()

    def _do_refresh(self) -> None:
        entries = scan_keybinds()
        GLib.idle_add(self._apply_refresh, entries)

    def _apply_refresh(self, entries: list[KeybindEntry]) -> bool:
        self._entries = entries
        self._refilter()
        return GLib.SOURCE_REMOVE

    def _on_search_changed(self, _entry: Gtk.SearchEntry) -> None:
        self._refilter()

    def _refilter(self) -> None:
        q = self._search.get_text().strip().lower()
        if not q:
            self._filtered = list(self._entries)
        else:
            self._filtered = [
                e
                for e in self._entries
                if q in e.combo.lower()
                or q in e.dispatcher.lower()
                or q in e.args.lower()
                or q in e.source_name.lower()
                or q in e.bind_type.lower()
                or ("owned" in q and e.owned)
                or ("locked" in q and not e.owned)
            ]

        while row := self._list.get_row_at_index(0):
            self._list.remove(row)

        # Group entries by category, preserving CATEGORY_ORDER
        grouped: dict[str, list[KeybindEntry]] = {c: [] for c in CATEGORY_ORDER}
        for entry in self._filtered:
            cat = _categorize_dispatcher(entry.dispatcher)
            grouped.setdefault(cat, []).append(entry)

        for cat in CATEGORY_ORDER:
            entries = grouped.get(cat, [])
            if not entries:
                continue
            self._list.append(self._make_category_header(cat))
            for entry in entries:
                self._list.append(self._make_row(entry))

        total = len(self._entries)
        visible = len(self._filtered)
        if q:
            self._count.set_text(f"{visible}/{total}")
        else:
            self._count.set_text(str(total))

    def _make_category_header(self, cat_id: str) -> Gtk.ListBoxRow:
        """Non-selectable section header row for a keybind category."""
        label_text, icon_name = CATEGORY_META.get(
            cat_id, (cat_id.title(), "applications-other-symbolic")
        )
        count = sum(
            1
            for e in self._filtered
            if _categorize_dispatcher(e.dispatcher) == cat_id
        )
        row = Gtk.ListBoxRow()
        row.set_activatable(False)
        row.set_selectable(False)
        row.add_css_class("keybind-cat-header")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.set_margin_start(14)
        box.set_margin_end(12)
        box.set_margin_top(12)
        box.set_margin_bottom(3)

        icon = Gtk.Image.new_from_icon_name(icon_name)
        icon.add_css_class("dim-label")
        icon.set_icon_size(Gtk.IconSize.NORMAL)

        lbl = Gtk.Label(label=label_text)
        lbl.add_css_class("keybind-cat-title")
        lbl.set_xalign(0)
        lbl.set_hexpand(True)

        count_lbl = Gtk.Label(label=f"{count} keybinds")
        count_lbl.add_css_class("caption")
        count_lbl.add_css_class("dim-label")

        box.append(icon)
        box.append(lbl)
        box.append(count_lbl)
        row.set_child(box)
        return row

    def _make_row(self, entry: KeybindEntry) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._entry = entry  # type: ignore[attr-defined]
        row.set_activatable(False)
        row.add_css_class("keybind-row-card")

        outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        outer.set_margin_start(12)
        outer.set_margin_end(12)
        outer.set_margin_top(3)
        outer.set_margin_bottom(3)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_start(14)
        box.set_margin_end(6)
        box.set_margin_top(9)
        box.set_margin_bottom(9)
        box.set_hexpand(True)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        combo = Gtk.Label(label=entry.combo)
        combo.add_css_class("keybind-combo")
        combo.set_xalign(0)
        combo.set_hexpand(True)
        combo.set_ellipsize(Pango.EllipsizeMode.END)

        state_badge = Gtk.Label(label="owned" if entry.owned else "locked")
        state_badge.add_css_class("caption")
        state_badge.add_css_class("manager-badge")
        state_badge.add_css_class(
            "keybind-badge-owned" if entry.owned else "keybind-badge-locked"
        )

        top.append(combo)
        top.append(state_badge)

        disp_head = entry.dispatcher.lower().split()[0] if entry.dispatcher.strip() else ""
        if disp_head in ("exec", "execr", "pass"):
            action_text = f"Run command: {entry.args or entry.dispatcher}"
        else:
            action_text = f"Action: {entry.dispatcher}" if entry.dispatcher else "Action: (unknown)"
            if entry.args:
                action_text = f"{action_text} {entry.args}"
        action = Gtk.Label(label=action_text)
        action.set_xalign(0)
        action.set_wrap(False)
        action.set_ellipsize(Pango.EllipsizeMode.END)
        action.add_css_class("keybind-action")
        action.add_css_class("dim-label")

        box.append(top)
        box.append(action)
        outer.append(box)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        actions.set_margin_end(8)
        actions.set_valign(Gtk.Align.CENTER)

        edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
        edit_btn.add_css_class("flat")
        edit_btn.add_css_class("circular")
        edit_btn.add_css_class("keybind-white-btn")
        edit_btn.set_tooltip_text("Edit keybind")
        edit_btn.connect("clicked", self._on_inline_edit_clicked, entry)
        actions.append(edit_btn)

        if entry.owned:
            remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
            remove_btn.add_css_class("flat")
            remove_btn.add_css_class("circular")
            remove_btn.add_css_class("keybind-white-btn")
            remove_btn.set_tooltip_text("Remove keybind")
            remove_btn.connect("clicked", self._on_inline_remove_clicked, entry)
            actions.append(remove_btn)
        else:
            lock_btn = Gtk.Button(icon_name="changes-prevent-symbolic")
            lock_btn.add_css_class("flat")
            lock_btn.add_css_class("circular")
            lock_btn.add_css_class("keybind-white-btn")
            lock_btn.set_sensitive(False)
            lock_btn.set_tooltip_text("Locked keybind")
            actions.append(lock_btn)

        outer.append(actions)

        row.set_child(outer)
        return row

    def _on_add_clicked(self, _btn: Gtk.Button) -> None:
        dialog = KeybindEditDialog(
            window=self,
            toast_overlay=self._toast_ov,
            on_apply=self._on_dialog_apply,
        )
        dialog.present(self.get_root())

    def _on_dialog_apply(self, entry: KeybindEntry) -> None:
        threading.Thread(target=self._do_add_keybind, args=(entry,), daemon=True).start()

    def _on_inline_edit_clicked(self, _btn: Gtk.Button, entry: KeybindEntry) -> None:
        edited = KeybindEntry(
            mods=entry.mods,
            key=entry.key,
            combo=entry.combo,
            bind_type=entry.bind_type,
            dispatcher=entry.dispatcher,
            args=entry.args,
            raw_line=entry.raw_line,
            owned=entry.owned,
            source_name=entry.source_name,
            line_no=entry.line_no,
        )
        dialog = KeybindEditDialog(
            window=self,
            toast_overlay=self._toast_ov,
            entry=edited,
            on_apply=lambda new_entry, old_entry=entry: self._on_dialog_edit_apply(old_entry, new_entry),
        )
        dialog.present(self.get_root())

    def _on_dialog_edit_apply(self, old_entry: KeybindEntry, new_entry: KeybindEntry) -> None:
        if old_entry.owned:
            threading.Thread(
                target=self._do_update_keybind,
                args=(old_entry, new_entry),
                daemon=True,
            ).start()
            return
        threading.Thread(target=self._do_add_keybind, args=(new_entry,), daemon=True).start()

    def _do_update_keybind(self, old_entry: KeybindEntry, new_entry: KeybindEntry) -> None:
        from lib import utility

        try:
            ok, msg = update_keybind(old_entry, new_entry)
            if not ok:
                GLib.idle_add(self._toast, msg)
                return
        except Exception as exc:
            GLib.idle_add(self._toast, f"Failed to update keybind: {exc}")
            return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        utility.toast(self._toast_ov, "Keybind updated — Hyprland reloaded")
        GLib.idle_add(self._after_edit_refresh)

    def _do_add_keybind(self, entry: KeybindEntry) -> None:
        from lib import utility

        try:
            ok, msg = add_keybind(entry)
            if not ok:
                GLib.idle_add(self._toast, msg)
                return
        except Exception as exc:
            GLib.idle_add(self._toast, f"Failed to add keybind: {exc}")
            return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        utility.toast(self._toast_ov, "Keybind added — Hyprland reloaded")
        GLib.idle_add(self._after_edit_refresh)

    def _on_inline_remove_clicked(self, _btn: Gtk.Button, entry: KeybindEntry) -> None:
        """Remove button clicked directly on a row."""
        if not entry.owned:
            return
        threading.Thread(target=self._do_remove_keybind, args=(entry,), daemon=True).start()

    def _do_remove_keybind(self, entry: KeybindEntry) -> None:
        from lib import utility

        if not entry.owned:
            GLib.idle_add(self._toast, "Cannot remove a locked keybind")
            return

        try:
            ok, msg = remove_keybind(entry)
            if not ok:
                GLib.idle_add(self._toast, msg)
                return
        except Exception as exc:
            GLib.idle_add(self._toast, f"Failed to remove keybind: {exc}")
            return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        utility.toast(self._toast_ov, "Keybind removed — Hyprland reloaded")
        GLib.idle_add(self._after_edit_refresh)

    def _on_reload_clicked(self, _btn: Gtk.Button) -> None:
        from lib import utility

        threading.Thread(
            target=lambda: subprocess.run(["hyprctl", "reload"], capture_output=True),
            daemon=True,
        ).start()
        utility.toast(self._toast_ov, "Hyprland reloading…")

    def _after_edit_refresh(self) -> bool:
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _toast(self, message: str) -> bool:
        from lib import utility

        utility.toast(self._toast_ov, message)
        return GLib.SOURCE_REMOVE
