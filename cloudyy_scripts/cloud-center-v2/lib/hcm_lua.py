"""
Cloud Center — lib/hcm_lua.py
Manages the single ~/.config/hypr/<name>.lua file per Hyprland module.

There is no more distro-vs-user-override split: every module is one file,
seeded once from install/default-theme/hypr/ and edited in place forever
after. "Reset to shipped defaults" copies the seed file back over the live
one; there is nothing else to activate or revert.
"""
from __future__ import annotations

import logging
import os
import re
import subprocess
import tempfile
import threading
from dataclasses import dataclass
from pathlib import Path

from gi.repository import Adw, GLib, Gtk, Pango

from lib import utility

log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────

HYPR_DIR = Path.home() / ".config" / "hypr"
MAIN_LUA = HYPR_DIR / "hyprland.lua"
DEFAULTS_DIR = Path.home() / "cloudyy-linux" / "install" / "default-theme" / "hypr"

MODULE_NAMES = [
    "bindings", "lookandfeel", "animations", "input", "cursor",
    "monitors", "autostart", "windowrules", "variables", "colors",
]


# ── Atomic writes ─────────────────────────────────────────────────────────────

def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    Path(tmp_path).replace(path)


# ── Reset to shipped defaults ─────────────────────────────────────────────────

def reset_to_default(module: str) -> tuple[bool, str]:
    # Note: this is the coarse "reset" — a whole-file replace from the shipped
    # seed. For lookandfeel/input/animations specifically, that seed ships a
    # POPULATED managed block (real personal defaults, e.g. border_size = 1),
    # not an empty one — see the plan's "ship personal content as default"
    # decision. That makes this a different, coarser operation than
    # hypr_layout_persist.reset_page()/hypr_animations_persist.clear_key(),
    # which surgically clear per-key state and fall back to the static distro
    # body (e.g. border_size = 0) instead. Both are correct as designed; a
    # caller wiring up a "reset" UI action should be intentional about which
    # one it actually means to invoke.
    default_path = DEFAULTS_DIR / f"{module}.lua"
    if not default_path.exists():
        return False, f"No shipped default for {module}"
    content = default_path.read_text(encoding="utf-8")
    atomic_write(HYPR_DIR / f"{module}.lua", content)
    return True, f"Reset {module}.lua to shipped defaults"


# ── Description parsing ───────────────────────────────────────────────────────

def _read_lua_description(path: Path) -> str:
    """
    Read the optional  -- @description = <text>  tag from anywhere in the
    first 10 lines, or fall back to the first non-empty comment line.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()[:10]
    except OSError:
        return "No description available."

    for line in lines:
        m = re.match(r"--\s*@description\s*=\s*(.+)", line)
        if m:
            return m.group(1).strip()

    for line in lines:
        m = re.match(r"--\s*(.+)", line)
        if m:
            text = m.group(1).strip()
            if text and not text.startswith("-"):
                return text

    return "No description available."


# ── Module listing ────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class ModuleInfo:
    filename: str
    path: Path
    description: str


def scan_modules() -> list[ModuleInfo]:
    """List every ~/.config/hypr/<name>.lua that currently exists."""
    modules = []
    for name in MODULE_NAMES:
        path = HYPR_DIR / f"{name}.lua"
        if path.exists():
            modules.append(ModuleInfo(
                filename=f"{name}.lua",
                path=path,
                description=_read_lua_description(path),
            ))
    return modules


def _preview_lines(path: Path, max_lines: int = 60) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(lines[:max_lines])
    except OSError:
        return "(could not read file)"


# ── GTK4 Page ─────────────────────────────────────────────────────────────────

class LuaConfigManagerPage(Gtk.Box):
    """
    Two-panel config manager for ~/.config/hypr/<name>.lua modules.
    Left:  scrollable file list.
    Right: description, preview, Edit / Reset-to-shipped-defaults buttons.
    """

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov = toast_overlay
        self._files: list[ModuleInfo] = []
        self._selected: ModuleInfo | None = None

        self._build_ui()
        self.refresh()

    def _build_ui(self) -> None:
        # ── Left panel ───────────────────────────────────────────────────────
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(260, -1)

        list_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        list_header.set_margin_start(12)
        list_header.set_margin_end(8)
        list_header.set_margin_top(10)
        list_header.set_margin_bottom(4)

        list_title = Gtk.Label(label="Lua Modules")
        list_title.add_css_class("heading")
        list_title.set_hexpand(True)
        list_title.set_xalign(0)

        self._file_count = Gtk.Label(label="")
        self._file_count.add_css_class("dim-label")
        self._file_count.add_css_class("caption")

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Reload file list")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        list_header.append(list_title)
        list_header.append(self._file_count)
        list_header.append(refresh_btn)
        left.append(list_header)

        self._file_search = Gtk.SearchEntry()
        self._file_search.set_placeholder_text("Filter modules…")
        self._file_search.set_margin_start(8)
        self._file_search.set_margin_end(8)
        self._file_search.set_margin_bottom(6)
        self._file_search.connect("search-changed", self._on_search_changed)
        left.append(self._file_search)
        left.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        self._list_box = Gtk.ListBox()
        self._list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list_box.add_css_class("navigation-sidebar")
        self._list_box.connect("row-selected", self._on_row_selected)

        list_scroll = Gtk.ScrolledWindow()
        list_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        list_scroll.set_vexpand(True)
        list_scroll.set_child(self._list_box)
        left.append(list_scroll)

        # ── Right panel ──────────────────────────────────────────────────────
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        right.set_hexpand(True)

        info_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        info_card.add_css_class("card")
        info_card.set_margin_start(14)
        info_card.set_margin_end(14)
        info_card.set_margin_top(14)
        info_card.set_margin_bottom(8)

        self._filename_label = Gtk.Label(label="Select a module to view details.")
        self._filename_label.add_css_class("heading")
        self._filename_label.set_xalign(0)

        self._desc_label = Gtk.Label(label="")
        self._desc_label.set_wrap(True)
        self._desc_label.set_xalign(0)
        self._desc_label.set_max_width_chars(60)
        self._desc_label.add_css_class("dim-label")
        self._desc_label.add_css_class("caption")

        info_card.append(self._filename_label)
        info_card.append(self._desc_label)
        right.append(info_card)

        action_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        action_bar.set_margin_start(14)
        action_bar.set_margin_end(14)
        action_bar.set_margin_bottom(8)

        self._editor = (
            os.environ.get("EDITOR") or os.environ.get("VISUAL") or "nvim"
        )
        editor_display = Path(self._editor).name

        self._edit_btn = Gtk.Button()
        edit_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        edit_box.append(Gtk.Image.new_from_icon_name("document-edit-symbolic"))
        edit_box.append(Gtk.Label(label=f"Edit in {editor_display}"))
        self._edit_btn.set_child(edit_box)
        self._edit_btn.add_css_class("suggested-action")
        self._edit_btn.set_sensitive(False)
        self._edit_btn.connect("clicked", self._on_edit_clicked)

        self._revert_btn = Gtk.Button()
        revert_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        revert_box.append(Gtk.Image.new_from_icon_name("edit-undo-symbolic"))
        revert_box.append(Gtk.Label(label="Reset to shipped defaults"))
        self._revert_btn.set_child(revert_box)
        self._revert_btn.add_css_class("flat")
        self._revert_btn.add_css_class("destructive-action")
        self._revert_btn.set_sensitive(False)
        self._revert_btn.set_tooltip_text("Overwrite with the shipped default, discarding your edits")
        self._revert_btn.connect("clicked", self._on_revert_clicked)

        spacer = Gtk.Box()
        spacer.set_hexpand(True)

        self._reload_btn = Gtk.Button(icon_name="system-reboot-symbolic")
        self._reload_btn.add_css_class("flat")
        self._reload_btn.set_tooltip_text("Reload Hyprland")
        self._reload_btn.connect("clicked", self._on_reload_clicked)

        action_bar.append(self._edit_btn)
        action_bar.append(self._revert_btn)
        action_bar.append(spacer)
        action_bar.append(self._reload_btn)
        right.append(action_bar)

        preview_hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        preview_hdr.set_margin_start(14)
        preview_hdr.set_margin_end(14)
        preview_hdr.set_margin_bottom(4)

        preview_label = Gtk.Label(label="Preview")
        preview_label.add_css_class("heading")
        preview_label.set_xalign(0)
        preview_label.set_hexpand(True)

        self._preview_lines_label = Gtk.Label(label="")
        self._preview_lines_label.add_css_class("dim-label")
        self._preview_lines_label.add_css_class("caption")

        preview_hdr.append(preview_label)
        preview_hdr.append(self._preview_lines_label)
        right.append(preview_hdr)

        self._preview_buf  = Gtk.TextBuffer()
        self._preview_view = Gtk.TextView(buffer=self._preview_buf)
        self._preview_view.set_editable(False)
        self._preview_view.set_cursor_visible(False)
        self._preview_view.set_monospace(True)
        self._preview_view.set_margin_start(4)
        self._preview_view.set_margin_end(4)
        self._preview_view.add_css_class("card")

        preview_scroll = Gtk.ScrolledWindow()
        preview_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        preview_scroll.set_vexpand(True)
        preview_scroll.set_margin_start(14)
        preview_scroll.set_margin_end(14)
        preview_scroll.set_margin_bottom(14)
        preview_scroll.set_child(self._preview_view)
        right.append(preview_scroll)

        vsep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.append(left)
        self.append(vsep)
        self.append(right)

    # ── Data ──────────────────────────────────────────────────────────────────

    def refresh(self) -> None:
        threading.Thread(target=self._do_refresh, daemon=True).start()

    def _do_refresh(self) -> None:
        files = scan_modules()
        GLib.idle_add(self._apply_refresh, files)

    def _apply_refresh(self, files: list[ModuleInfo]) -> bool:
        prev = self._selected.filename if self._selected else None
        self._files = files
        self._relist(prev)
        return GLib.SOURCE_REMOVE

    def _on_search_changed(self, _entry: Gtk.SearchEntry) -> None:
        self._relist(self._selected.filename if self._selected else None)

    def _relist(self, reselect: str | None = None) -> None:
        q        = self._file_search.get_text().strip().lower()
        filtered = [
            cf for cf in self._files
            if not q or q in cf.filename.lower() or q in cf.description.lower()
        ]

        while row := self._list_box.get_row_at_index(0):
            self._list_box.remove(row)

        for cf in filtered:
            self._list_box.append(self._make_row(cf))

        total = len(self._files)
        if q:
            self._file_count.set_text(f"{len(filtered)}/{total}")
        else:
            self._file_count.set_text(f"{total} modules")

        for i, cf in enumerate(filtered):
            if cf.filename == reselect:
                row = self._list_box.get_row_at_index(i)
                if row:
                    self._list_box.select_row(row)
                break

    def _make_row(self, cf: ModuleInfo) -> Gtk.ListBoxRow:
        row      = Gtk.ListBoxRow()
        row._cf  = cf  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(8)
        box.set_margin_top(7)
        box.set_margin_bottom(7)

        icon = Gtk.Image.new_from_icon_name("text-x-script-symbolic")
        icon.set_icon_size(Gtk.IconSize.NORMAL)

        lbl = Gtk.Label(label=cf.filename)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)

        box.append(icon)
        box.append(lbl)
        row.set_child(box)
        return row

    # ── Events ────────────────────────────────────────────────────────────────

    def _on_row_selected(self, _listbox: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if row is None:
            self._selected = None
            self._edit_btn.set_sensitive(False)
            self._revert_btn.set_sensitive(False)
            return

        cf = getattr(row, "_cf", None)
        if cf is None:
            return
        self._selected = cf

        self._filename_label.set_text(cf.filename)
        self._desc_label.set_text(cf.description)

        self._edit_btn.set_sensitive(True)
        self._revert_btn.set_sensitive(True)

        threading.Thread(
            target=self._load_preview, args=(cf,), daemon=True
        ).start()

    def _load_preview(self, cf: ModuleInfo) -> None:
        path = cf.path
        text = _preview_lines(path)
        try:
            total_lines = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError:
            total_lines = 0
        GLib.idle_add(self._apply_preview, text, path.name, total_lines)

    def _apply_preview(self, text: str, filename: str, line_count: int) -> bool:
        self._preview_buf.set_text(text)
        self._preview_lines_label.set_text(f"{line_count} lines  ·  {filename}")
        return GLib.SOURCE_REMOVE

    def _on_edit_clicked(self, _btn: Gtk.Button) -> None:
        if self._selected is None:
            return
        self._edit_btn.set_sensitive(False)
        threading.Thread(target=self._do_edit, args=(self._selected,), daemon=True).start()

    def _do_edit(self, cf: ModuleInfo) -> None:
        edit_path = cf.path
        try:
            subprocess.run(
                ["kitty", "--class", "hcm-editor",
                 "--title", f"Editing {cf.filename}",
                 "--", self._editor, str(edit_path)],
                check=False,
            )
        except FileNotFoundError:
            try:
                subprocess.run(
                    ["bash", "-c", f'{self._editor} "{edit_path}"'],
                    check=False,
                )
            except Exception as e:
                GLib.idle_add(self._edit_done, f"Editor launch failed: {e}")
                return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        GLib.idle_add(self._edit_done, f"Edited {cf.filename} — Hyprland reloaded")

    def _edit_done(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self._edit_btn.set_sensitive(True)
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_revert_clicked(self, _btn: Gtk.Button) -> None:
        if self._selected is None:
            return
        self._revert_btn.set_sensitive(False)
        self._edit_btn.set_sensitive(False)
        threading.Thread(target=self._do_revert, args=(self._selected,), daemon=True).start()

    def _do_revert(self, cf: ModuleInfo) -> None:
        ok, msg = reset_to_default(cf.path.stem)
        if ok:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            msg += " — Hyprland reloaded"
        GLib.idle_add(self._revert_done, msg)

    def _revert_done(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self._edit_btn.set_sensitive(True)
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_reload_clicked(self, _btn: Gtk.Button) -> None:
        from lib import utility
        threading.Thread(
            target=lambda: subprocess.run(["hyprctl", "reload"], capture_output=True),
            daemon=True,
        ).start()
        utility.toast(self._toast_ov, "Hyprland reloading…")
