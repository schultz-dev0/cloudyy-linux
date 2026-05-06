"""
Cloud Center — lib/keybind_manager_lua.py
Lua keybind manager: mirrors keybind_manager.py but targets
~/.config/hypr/.hyprlua/bindings.lua and parses hl.bind(...) calls.

Writes/reads a Cloud Center-managed section delimited by:
  -- --- Cloud Center Additions (managed by Cloud Center) ---
  -- --- End Cloud Center Additions ---

NOT wired into the Cloud Center UI yet — logic layer only.
"""
from __future__ import annotations

import logging
import os
import re
import tempfile
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from gi.repository import Adw, Gdk, GLib, Gtk, Pango

import lib.hcm_lua as hcm_lua

log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────

BINDINGS_LUA  = hcm_lua.HYPRLUA_DIR / "bindings.lua"
MAIN_LUA      = hcm_lua.MAIN_LUA
_BINDINGS_REQ = 'require("bindings")'

_CC_BEGIN = '-- --- Cloud Center Additions (managed by Cloud Center) ---'
_CC_END   = '-- --- End Cloud Center Additions ---'


# ── Dispatcher categories (same as keybind_manager.py) ───────────────────────

DISPATCHER_CATEGORIES = [
    {"id": "workspace", "label": "Workspace Navigation", "icon": "shell-overview-symbolic"},
    {"id": "window",    "label": "Window Management",    "icon": "overlapping-windows-symbolic"},
    {"id": "app",       "label": "Launch Application",   "icon": "system-run-symbolic"},
    {"id": "other",     "label": "Other / Special",      "icon": "terminal-symbolic"},
]

DISPATCHER_MAP: dict[str, list[str]] = {
    "workspace": [
        "hl.dsp.focus workspace",
        "hl.dsp.window.move workspace",
        "hl.dsp.workspace.toggle_special",
        "hl.dsp.workspace.rename",
        "hl.dsp.workspace.move",
        "hl.dsp.workspace.swap_monitors",
    ],
    "window": [
        "hl.dsp.window.close",
        "hl.dsp.window.kill",
        "hl.dsp.window.float",
        "hl.dsp.window.fullscreen",
        "hl.dsp.window.pseudo",
        "hl.dsp.window.move direction",
        "hl.dsp.focus direction",
        "hl.dsp.window.cycle_next",
        "hl.dsp.window.center",
        "hl.dsp.window.pin",
        "hl.dsp.window.resize",
        "hl.dsp.window.set_prop",
        "hl.dsp.window.drag",
    ],
    "app": [
        "hl.dsp.exec_cmd",
        "hl.dsp.exec_raw",
    ],
    "other": [
        "hl.dsp.exit",
        "hl.dsp.dpms",
        "hl.dsp.layout",
        "hl.dsp.submap",
        "hl.dsp.global",
        "hl.dsp.event",
    ],
}

CATEGORY_ORDER: list[str]                   = ["workspace", "window", "app", "other"]
CATEGORY_META:  dict[str, tuple[str, str]]  = {
    "workspace": ("Workspace Navigation", "shell-overview-symbolic"),
    "window":    ("Window Management",    "overlapping-windows-symbolic"),
    "app":       ("Applications",         "system-run-symbolic"),
    "other":     ("Other / Special",      "terminal-symbolic"),
}


def _categorize_dispatcher(dispatcher: str) -> str:
    d = dispatcher.strip()
    if "exec_cmd" in d or "exec_raw" in d:
        return "app"
    if "workspace" in d or "toggle_special" in d:
        return "workspace"
    if any(x in d for x in ("window.", "focus", "cycle_next", "center", "pin", "resize", "drag", "set_prop")):
        return "window"
    return "other"


# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class LuaKeybindEntry:
    keys:        str          # e.g. "SUPER + W"
    dispatcher:  str          # e.g. 'hl.dsp.window.close()'
    opts:        str          # e.g. '{ desc = "Kill window" }' (raw string, may be empty)
    raw_line:    str          # original source line
    owned:       bool         # True if inside CC section
    source_name: str = ""
    line_no:     int  = 0

    @property
    def combo(self) -> str:
        return self.keys.replace('"', "").strip()


# ── Parsing helpers ───────────────────────────────────────────────────────────

# Matches: hl.bind("KEYS", dispatcher_expr, opts?)
# dispatcher_expr may contain nested parens like hl.dsp.exec_cmd("cmd")
_BIND_RE = re.compile(
    r'hl\.bind\(\s*'
    r'"([^"]+)"'              # group 1: key string
    r'\s*,\s*'
    r'(hl\.dsp\.[^,\n]+?)'   # group 2: dispatcher (greedy but not past newline)
    r'(?:\s*,\s*(\{[^}]*\}))?' # group 3: optional opts table
    r'\s*\)',
    re.DOTALL,
)


def _parse_bind_line(line: str) -> Optional[LuaKeybindEntry]:
    """Return a LuaKeybindEntry from an hl.bind(...) line, or None."""
    stripped = line.strip()
    if not stripped or stripped.startswith("--"):
        return None
    m = _BIND_RE.search(stripped)
    if not m:
        return None
    keys       = m.group(1).strip()
    dispatcher = m.group(2).strip()
    opts       = (m.group(3) or "").strip()
    return LuaKeybindEntry(
        keys       = keys,
        dispatcher = dispatcher,
        opts       = opts,
        raw_line   = stripped,
        owned      = False,
    )


def _entry_to_line(entry: LuaKeybindEntry) -> str:
    """Render a LuaKeybindEntry back to an hl.bind(...) source line."""
    if entry.opts:
        return f'hl.bind("{entry.keys}", {entry.dispatcher}, {entry.opts})'
    return f'hl.bind("{entry.keys}", {entry.dispatcher})'


# ── File I/O ──────────────────────────────────────────────────────────────────

def _ensure_bindings_lua() -> None:
    """Ensure bindings.lua exists, has a CC marker section, and is required by hyprland.lua."""
    if not BINDINGS_LUA.exists():
        hcm_lua.HYPRLUA_DIR.mkdir(parents=True, exist_ok=True)
        BINDINGS_LUA.write_text(
            "-- Cloud Center — Lua keybind additions\n\n"
            f"{_CC_BEGIN}\n{_CC_END}\n",
            encoding="utf-8",
        )
        log.info("Created %s", BINDINGS_LUA)

    text = BINDINGS_LUA.read_text(encoding="utf-8")
    if _CC_BEGIN not in text:
        with open(BINDINGS_LUA, "a", encoding="utf-8") as f:
            f.write(f"\n{_CC_BEGIN}\n{_CC_END}\n")

    # Ensure hyprland.lua requires bindings
    _ensure_require_in_main()


def _ensure_require_in_main() -> None:
    """Add require("bindings") to hyprland.lua if missing."""
    if not MAIN_LUA.exists():
        return
    content = MAIN_LUA.read_text(encoding="utf-8")
    if _BINDINGS_REQ in content:
        return
    with open(MAIN_LUA, "a", encoding="utf-8") as f:
        f.write(f"\n{_BINDINGS_REQ}\n")
    log.info("Appended %s to %s", _BINDINGS_REQ, MAIN_LUA)


def _read_cc_section(text: str) -> str:
    m = re.search(
        re.escape(_CC_BEGIN) + r"\n(.*?)" + re.escape(_CC_END),
        text,
        re.DOTALL,
    )
    return m.group(1) if m else ""


def _get_cc_lines() -> list[str]:
    if not BINDINGS_LUA.exists():
        return []
    text = BINDINGS_LUA.read_text(encoding="utf-8", errors="replace")
    cc_text = _read_cc_section(text)
    return [ln for ln in cc_text.splitlines() if ln.strip() and not ln.strip().startswith("--")]


def _write_cc_section(lines: list[str]) -> None:
    _ensure_bindings_lua()
    text       = BINDINGS_LUA.read_text(encoding="utf-8", errors="replace")
    cc_content = "\n".join(lines)
    if cc_content:
        cc_content += "\n"

    if _CC_BEGIN in text:
        pattern     = re.escape(_CC_BEGIN) + r".*?" + re.escape(_CC_END)
        replacement = f"{_CC_BEGIN}\n{cc_content}{_CC_END}"
        new_text    = re.sub(pattern, replacement, text, flags=re.DOTALL)
    else:
        new_text = text.rstrip() + f"\n{_CC_BEGIN}\n{cc_content}{_CC_END}\n"

    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(BINDINGS_LUA.parent))
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.write(new_text)
        f.flush()
        os.fsync(f.fileno())
    Path(tmp_path).replace(BINDINGS_LUA)


# ── Public API ────────────────────────────────────────────────────────────────

def scan_keybinds() -> list[LuaKeybindEntry]:
    """
    Scan bindings.lua and return all hl.bind() entries.

    Entries inside the CC section are marked owned=True.
    Entries before the CC section marker are locked (owned=False).
    """
    _ensure_bindings_lua()

    if not BINDINGS_LUA.exists():
        return []

    full_text  = BINDINGS_LUA.read_text(encoding="utf-8", errors="replace")
    cc_section = _read_cc_section(full_text)
    before     = full_text.split(_CC_BEGIN)[0] if _CC_BEGIN in full_text else full_text

    owned: list[LuaKeybindEntry]  = []
    locked: list[LuaKeybindEntry] = []

    for idx, raw in enumerate(cc_section.splitlines(), 1):
        e = _parse_bind_line(raw)
        if e:
            e.owned       = True
            e.source_name = BINDINGS_LUA.name
            e.line_no     = idx
            owned.append(e)

    for idx, raw in enumerate(before.splitlines(), 1):
        e = _parse_bind_line(raw)
        if e:
            e.owned       = False
            e.source_name = BINDINGS_LUA.name
            e.line_no     = idx
            locked.append(e)

    merged = owned + locked
    merged.sort(key=lambda e: (not e.owned, e.combo.lower()))
    return merged


def add_keybind(entry: LuaKeybindEntry) -> tuple[bool, str]:
    _ensure_bindings_lua()
    lines = _get_cc_lines()
    lines.append(_entry_to_line(entry))
    _write_cc_section(lines)
    return True, "keybind added"


def remove_keybind(entry: LuaKeybindEntry) -> tuple[bool, str]:
    if not BINDINGS_LUA.exists():
        return False, "bindings.lua not found"
    target = _entry_to_line(entry).strip()
    lines  = _get_cc_lines()
    out    = [ln for ln in lines if ln.strip() != target]
    if len(out) == len(lines):
        return False, "keybind not found"
    _write_cc_section(out)
    return True, "keybind removed"


def update_keybind(old: LuaKeybindEntry, new: LuaKeybindEntry) -> tuple[bool, str]:
    if not BINDINGS_LUA.exists():
        return False, "bindings.lua not found"
    old_line = _entry_to_line(old).strip()
    new_line = _entry_to_line(new)
    lines    = _get_cc_lines()
    replaced = False
    out: list[str] = []
    for ln in lines:
        if not replaced and ln.strip() == old_line:
            out.append(new_line)
            replaced = True
        else:
            out.append(ln)
    if not replaced:
        return False, "keybind not found"
    _write_cc_section(out)
    return True, "keybind updated"


# ── Edit dialog ───────────────────────────────────────────────────────────────

class LuaKeybindEditDialog(Adw.Dialog):
    """
    Keybind edit dialog for Lua bindings.
    Structurally mirrors KeybindEditDialog from keybind_manager.py.
    Produces hl.bind("KEYS", hl.dsp.exec_cmd("cmd"), opts) lines.
    """

    def __init__(
        self,
        window: Gtk.Window,
        toast_overlay: Adw.ToastOverlay,
        entry: LuaKeybindEntry | None = None,
        on_apply=None,
    ) -> None:
        super().__init__()
        self._window   = window
        self._toast_ov = toast_overlay
        self._on_apply = on_apply
        self._capturing = False
        self._key_controller: Gtk.EventControllerKey | None = None
        self._key_controller_local: Gtk.EventControllerKey | None = None

        self._entry = entry or LuaKeybindEntry(
            keys       = "",
            dispatcher = "hl.dsp.exec_cmd(\"\")",
            opts       = "",
            raw_line   = "",
            owned      = True,
        )

        self.set_title("Add Keybind" if entry is None else "Edit Keybind")
        self.set_content_width(500)
        self.set_content_height(540)
        self._build_ui()

    def _build_ui(self) -> None:
        toolbar = Adw.ToolbarView()
        header  = Adw.HeaderBar()

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", self._on_cancel)
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

        # Key capture
        key_group = Adw.PreferencesGroup(title="Key Combination")
        self._capture_label = Gtk.Label(
            label=self._entry.keys or "Press Record to capture…"
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

        # Dispatcher
        disp_group = Adw.PreferencesGroup(title="Action")
        self._cat_combo = Adw.ComboRow(title="Category")
        cat_labels      = [c["label"] for c in DISPATCHER_CATEGORIES]
        self._cat_combo.set_model(Gtk.StringList.new(cat_labels))
        self._cat_combo.connect("notify::selected", self._on_cat_changed)
        disp_group.add(self._cat_combo)

        self._disp_combo = Adw.ComboRow(title="Dispatcher")
        disp_group.add(self._disp_combo)
        content.append(disp_group)

        # Command (for exec_cmd)
        self._cmd_row = Adw.EntryRow(title="Command")
        cmd = self._extract_cmd(self._entry.dispatcher)
        self._cmd_row.set_text(cmd)
        content.append(self._cmd_row)

        # Options
        self._opts_row = Adw.EntryRow(title="Options (Lua table, e.g. { locked = true })")
        self._opts_row.set_text(self._entry.opts or "")
        content.append(self._opts_row)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_child(content)
        toolbar.set_content(scroll)
        self.set_child(toolbar)

        self._populate_dispatchers()

    def _extract_cmd(self, dispatcher: str) -> str:
        m = re.search(r'exec_cmd\("([^"]*)"\)', dispatcher)
        return m.group(1) if m else ""

    def _populate_dispatchers(self) -> None:
        idx    = self._cat_combo.get_selected()
        cat_id = DISPATCHER_CATEGORIES[idx]["id"] if idx < len(DISPATCHER_CATEGORIES) else "app"
        dsps   = DISPATCHER_MAP.get(cat_id, ["hl.dsp.exec_cmd"])
        self._disp_combo.set_model(Gtk.StringList.new(dsps))

        target = self._entry.dispatcher.split("(")[0]
        for i, d in enumerate(dsps):
            if d.split()[0] == target:
                self._disp_combo.set_selected(i)
                return
        self._disp_combo.set_selected(0)

    def _on_cat_changed(self, *_) -> None:
        self._populate_dispatchers()

    def _on_cancel(self, _btn: Gtk.Button) -> None:
        self._capture_stop()
        self.close()

    # ── Key capture (mirrors KeybindEditDialog) ───────────────────────────────

    _MOD_KEYS = frozenset({
        "Control_L", "Control_R", "Alt_L", "Alt_R", "Meta_L", "Meta_R",
        "Shift_L", "Shift_R", "Super_L", "Super_R",
        "Caps_Lock", "Num_Lock", "Scroll_Lock",
    })

    def _on_capture_start(self, _btn: Gtk.Button) -> None:
        if self._capturing:
            self._capture_stop()
            return
        self._capturing = True
        self._capture_btn.set_label("Press a key…")
        self._capture_btn.add_css_class("destructive-action")
        self._capture_btn.remove_css_class("suggested-action")
        self._capture_label.set_label("Waiting for key…")

        try:
            self.grab_focus()
        except Exception:
            pass

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
        self._capturing = False
        self._capture_btn.set_label("Record")
        self._capture_btn.remove_css_class("destructive-action")
        self._capture_btn.add_css_class("suggested-action")
        if self._key_controller_local is not None:
            self.remove_controller(self._key_controller_local)
            self._key_controller_local = None
        if self._key_controller is not None:
            getattr(self, "_key_root", self).remove_controller(self._key_controller)
            self._key_controller = None

    def _on_key_captured(self, _ctrl, keyval: int, _keycode: int, state) -> bool:
        key_name = Gdk.keyval_name(keyval)
        if not key_name:
            return True
        if key_name == "Escape":
            self._capture_label.set_label(self._entry.keys or "Press Record to capture…")
            self._capture_stop()
            return True
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

        all_parts     = mods + [key_name.upper()]
        self._entry.keys = " + ".join(all_parts)
        self._capture_label.set_label(self._entry.keys)
        self._capture_stop()
        return True

    # ── Apply ─────────────────────────────────────────────────────────────────

    def _on_apply_clicked(self, _btn: Gtk.Button) -> None:
        self._capture_stop()

        if not self._entry.keys:
            return

        idx    = self._disp_combo.get_selected()
        model  = self._disp_combo.get_model()
        if model and idx < model.get_n_items():
            disp_base = model.get_item(idx).get_string()
        else:
            disp_base = "hl.dsp.exec_cmd"

        # Build dispatcher string
        cmd = self._cmd_row.get_text().strip()
        if "exec_cmd" in disp_base:
            self._entry.dispatcher = f'hl.dsp.exec_cmd("{cmd}")'
        else:
            self._entry.dispatcher = f"{disp_base.split()[0]}()"

        self._entry.opts     = self._opts_row.get_text().strip()
        self._entry.raw_line = _entry_to_line(self._entry)

        if self._on_apply:
            self._on_apply(self._entry)
        self.close()


# ── Main Page ─────────────────────────────────────────────────────────────────

class LuaKeybindManagerPage(Gtk.Box):
    """
    Keybind manager page for Lua bindings.
    Structurally mirrors KeybindManagerPage from keybind_manager.py.
    NOT wired into cloud-center.py yet.
    """

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov = toast_overlay
        self._entries:  list[LuaKeybindEntry] = []
        self._filtered: list[LuaKeybindEntry] = []

        self._build_ui()
        self.refresh()

    def _build_ui(self) -> None:
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        panel.set_hexpand(True)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        header.set_margin_start(14)
        header.set_margin_end(10)
        header.set_margin_top(10)
        header.set_margin_bottom(6)

        title = Gtk.Label(label="Lua Keybinds")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._count = Gtk.Label(label="")
        self._count.add_css_class("dim-label")
        self._count.add_css_class("caption")

        self._add_btn = Gtk.Button(icon_name="list-add-symbolic")
        self._add_btn.add_css_class("flat")
        self._add_btn.set_tooltip_text("Add keybind")
        self._add_btn.connect("clicked", self._on_add_clicked)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Rescan keybinds")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        self._reload_btn = Gtk.Button(icon_name="system-reboot-symbolic")
        self._reload_btn.add_css_class("flat")
        self._reload_btn.set_tooltip_text("Reload Hyprland")
        self._reload_btn.connect("clicked", self._on_reload_clicked)

        header.append(title)
        header.append(self._count)
        header.append(self._add_btn)
        header.append(refresh_btn)
        header.append(self._reload_btn)
        panel.append(header)

        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search keybinds…")
        self._search.set_margin_start(12)
        self._search.set_margin_end(12)
        self._search.set_margin_bottom(6)
        self._search.connect("search-changed", self._on_search_changed)
        panel.append(self._search)
        panel.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

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

    def _apply_refresh(self, entries: list[LuaKeybindEntry]) -> bool:
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
                e for e in self._entries
                if q in e.combo.lower()
                or q in e.dispatcher.lower()
                or ("owned" in q and e.owned)
                or ("locked" in q and not e.owned)
            ]

        while row := self._list.get_row_at_index(0):
            self._list.remove(row)

        grouped: dict[str, list[LuaKeybindEntry]] = {c: [] for c in CATEGORY_ORDER}
        for e in self._filtered:
            cat = _categorize_dispatcher(e.dispatcher)
            grouped.setdefault(cat, []).append(e)

        for cat in CATEGORY_ORDER:
            entries = grouped.get(cat, [])
            if not entries:
                continue
            self._list.append(self._make_cat_header(cat))
            for entry in entries:
                self._list.append(self._make_row(entry))

        total   = len(self._entries)
        visible = len(self._filtered)
        self._count.set_text(f"{visible}/{total}" if q else str(total))

    def _make_cat_header(self, cat_id: str) -> Gtk.ListBoxRow:
        label_text, icon_name = CATEGORY_META.get(cat_id, (cat_id.title(), "applications-other-symbolic"))
        count = sum(1 for e in self._filtered if _categorize_dispatcher(e.dispatcher) == cat_id)

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

    def _make_row(self, entry: LuaKeybindEntry) -> Gtk.ListBoxRow:
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

        combo_lbl = Gtk.Label(label=entry.combo)
        combo_lbl.add_css_class("keybind-combo")
        combo_lbl.set_xalign(0)
        combo_lbl.set_hexpand(True)
        combo_lbl.set_ellipsize(Pango.EllipsizeMode.END)

        badge = Gtk.Label(label="owned" if entry.owned else "locked")
        badge.add_css_class("caption")
        badge.add_css_class("manager-badge")
        badge.add_css_class("keybind-badge-owned" if entry.owned else "keybind-badge-locked")

        top.append(combo_lbl)
        top.append(badge)

        action_lbl = Gtk.Label(label=entry.dispatcher)
        action_lbl.set_xalign(0)
        action_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        action_lbl.add_css_class("keybind-action")
        action_lbl.add_css_class("dim-label")

        box.append(top)
        box.append(action_lbl)
        outer.append(box)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=2)
        actions.set_margin_end(8)
        actions.set_valign(Gtk.Align.CENTER)

        edit_btn = Gtk.Button(icon_name="document-edit-symbolic")
        edit_btn.add_css_class("flat")
        edit_btn.add_css_class("circular")
        edit_btn.set_tooltip_text("Edit keybind")
        edit_btn.connect("clicked", self._on_edit_clicked, entry)
        actions.append(edit_btn)

        if entry.owned:
            del_btn = Gtk.Button(icon_name="user-trash-symbolic")
            del_btn.add_css_class("flat")
            del_btn.add_css_class("circular")
            del_btn.set_tooltip_text("Remove keybind")
            del_btn.connect("clicked", self._on_remove_clicked, entry)
            actions.append(del_btn)
        else:
            lock_btn = Gtk.Button(icon_name="changes-prevent-symbolic")
            lock_btn.add_css_class("flat")
            lock_btn.add_css_class("circular")
            lock_btn.set_sensitive(False)
            lock_btn.set_tooltip_text("Locked keybind")
            actions.append(lock_btn)

        outer.append(actions)
        row.set_child(outer)
        return row

    # ── Actions ───────────────────────────────────────────────────────────────

    def _on_add_clicked(self, _btn: Gtk.Button) -> None:
        LuaKeybindEditDialog(
            window        = self,
            toast_overlay = self._toast_ov,
            on_apply      = self._on_dialog_apply,
        ).present(self.get_root())

    def _on_dialog_apply(self, entry: LuaKeybindEntry) -> None:
        threading.Thread(target=self._do_add, args=(entry,), daemon=True).start()

    def _on_edit_clicked(self, _btn: Gtk.Button, entry: LuaKeybindEntry) -> None:
        import copy
        LuaKeybindEditDialog(
            window        = self,
            toast_overlay = self._toast_ov,
            entry         = copy.copy(entry),
            on_apply      = lambda new, old=entry: self._on_edit_apply(old, new),
        ).present(self.get_root())

    def _on_edit_apply(self, old: LuaKeybindEntry, new: LuaKeybindEntry) -> None:
        if old.owned:
            threading.Thread(target=self._do_update, args=(old, new), daemon=True).start()
        else:
            threading.Thread(target=self._do_add, args=(new,), daemon=True).start()

    def _on_remove_clicked(self, _btn: Gtk.Button, entry: LuaKeybindEntry) -> None:
        if entry.owned:
            threading.Thread(target=self._do_remove, args=(entry,), daemon=True).start()

    def _do_add(self, entry: LuaKeybindEntry) -> None:
        from lib import utility
        ok, msg = add_keybind(entry)
        if ok:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            utility.toast(self._toast_ov, "Keybind added — Hyprland reloaded")
            GLib.idle_add(self._after_edit)
        else:
            GLib.idle_add(self._toast, msg)

    def _do_update(self, old: LuaKeybindEntry, new: LuaKeybindEntry) -> None:
        from lib import utility
        ok, msg = update_keybind(old, new)
        if ok:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            utility.toast(self._toast_ov, "Keybind updated — Hyprland reloaded")
            GLib.idle_add(self._after_edit)
        else:
            GLib.idle_add(self._toast, msg)

    def _do_remove(self, entry: LuaKeybindEntry) -> None:
        from lib import utility
        ok, msg = remove_keybind(entry)
        if ok:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            utility.toast(self._toast_ov, "Keybind removed — Hyprland reloaded")
            GLib.idle_add(self._after_edit)
        else:
            GLib.idle_add(self._toast, msg)

    def _on_reload_clicked(self, _btn: Gtk.Button) -> None:
        from lib import utility
        threading.Thread(
            target=lambda: subprocess.run(["hyprctl", "reload"], capture_output=True),
            daemon=True,
        ).start()
        utility.toast(self._toast_ov, "Hyprland reloading…")

    def _after_edit(self) -> bool:
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _toast(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        return GLib.SOURCE_REMOVE
