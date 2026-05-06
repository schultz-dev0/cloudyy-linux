"""
Cloud Center — lib/hcm_lua.py
Lua config manager: mirrors hcm.py but targets ~/.config/hypr/.hyprlua/

The Lua config has no distro/user-override split at the file level — modules in
.hyprlua/ are the live files.  This manager lets the UI list them, show previews,
and open them for editing.  A "modified" badge is tracked by comparing current
content against a SHA-256 stored in .hyprlua/.defaults_sha/ on first scan.

NOT wired into the Cloud Center UI yet — logic layer only.
"""
from __future__ import annotations

import hashlib
import logging
import os
import re
import subprocess
import threading
from enum import Enum, auto
from pathlib import Path
from typing import Optional

from gi.repository import Adw, GLib, Gtk, Pango

log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────

HYPR_DIR      = Path.home() / ".config" / "hypr"
HYPRLUA_DIR   = HYPR_DIR / ".hyprlua"
MAIN_LUA      = HYPR_DIR / "hyprland.lua"
SHA_DIR       = HYPRLUA_DIR / ".defaults_sha"


# ── Data ──────────────────────────────────────────────────────────────────────

class LuaFileStatus(Enum):
    PRISTINE = auto()   # matches the stored baseline hash
    MODIFIED = auto()   # content has changed since baseline
    NEW      = auto()   # no baseline hash recorded yet


class LuaConfigFile:
    def __init__(self, filename: str, path: Path, description: str, status: LuaFileStatus):
        self.filename    = filename
        self.path        = path
        self.description = description
        self.status      = status


# ── Baseline hash helpers ─────────────────────────────────────────────────────

def _sha_path(filename: str) -> Path:
    return SHA_DIR / (filename + ".sha256")


def _file_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return ""


def _record_baseline(path: Path) -> None:
    """Store the current file hash as the baseline."""
    SHA_DIR.mkdir(parents=True, exist_ok=True)
    sha = _file_sha256(path)
    if sha:
        _sha_path(path.name).write_text(sha, encoding="utf-8")


def _baseline_sha(filename: str) -> str:
    p = _sha_path(filename)
    try:
        return p.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


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


# ── Logic ─────────────────────────────────────────────────────────────────────

def scan_lua_files() -> list[LuaConfigFile]:
    """Scan HYPRLUA_DIR for .lua module files and return annotated list."""
    if not HYPRLUA_DIR.exists():
        return []

    files: list[LuaConfigFile] = []
    for p in sorted(HYPRLUA_DIR.iterdir()):
        if not p.is_file() or p.suffix != ".lua":
            continue

        current_sha  = _file_sha256(p)
        baseline     = _baseline_sha(p.name)

        if not baseline:
            status = LuaFileStatus.NEW
        elif current_sha == baseline:
            status = LuaFileStatus.PRISTINE
        else:
            status = LuaFileStatus.MODIFIED

        files.append(LuaConfigFile(
            filename    = p.name,
            path        = p,
            description = _read_lua_description(p),
            status      = status,
        ))
    return files


def record_all_baselines() -> None:
    """Record baselines for every .lua file that doesn't have one yet."""
    for f in scan_lua_files():
        if f.status == LuaFileStatus.NEW:
            _record_baseline(f.path)


def revert_to_baseline(cf: LuaConfigFile) -> tuple[bool, str]:
    """
    Not directly supported — Lua files have no distro source to copy from.
    Returns an explanatory message.
    """
    return False, (
        f"{cf.filename} has no distro source to revert to. "
        "Edit the file manually or restore from git."
    )


def _preview_lines(path: Path, max_lines: int = 60) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(lines[:max_lines])
    except OSError:
        return "(could not read file)"


# ── GTK4 Page ─────────────────────────────────────────────────────────────────

class LuaConfigManagerPage(Gtk.Box):
    """
    Two-panel config manager for .hyprlua/ Lua modules.
    Left:  scrollable file list with pristine/modified badges.
    Right: description, status, preview, Edit button.

    Structurally mirrors ConfigManagerPage from hcm.py.
    NOT wired into cloud-center.py yet.
    """

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov = toast_overlay
        self._files: list[LuaConfigFile] = []
        self._selected: Optional[LuaConfigFile] = None

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

        self._desc_label = Gtk.Label(label="Select a module to view details.")
        self._desc_label.set_wrap(True)
        self._desc_label.set_xalign(0)
        self._desc_label.set_max_width_chars(60)

        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        status_row.set_margin_top(2)

        self._status_icon  = Gtk.Image()
        self._status_icon.set_icon_size(Gtk.IconSize.NORMAL)
        self._status_label = Gtk.Label()
        self._status_label.set_xalign(0)
        self._status_label.set_hexpand(True)
        self._status_label.add_css_class("caption")
        self._status_badge = Gtk.Label()
        self._status_badge.add_css_class("caption")
        self._status_badge.add_css_class("manager-badge")

        status_row.append(self._status_icon)
        status_row.append(self._status_label)
        status_row.append(self._status_badge)
        info_card.append(self._desc_label)
        info_card.append(status_row)
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

        spacer = Gtk.Box()
        spacer.set_hexpand(True)

        self._reload_btn = Gtk.Button(icon_name="system-reboot-symbolic")
        self._reload_btn.add_css_class("flat")
        self._reload_btn.set_tooltip_text("Reload Hyprland")
        self._reload_btn.connect("clicked", self._on_reload_clicked)

        action_bar.append(self._edit_btn)
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
        files = scan_lua_files()
        GLib.idle_add(self._apply_refresh, files)

    def _apply_refresh(self, files: list[LuaConfigFile]) -> bool:
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

        total    = len(self._files)
        modified = sum(1 for cf in self._files if cf.status == LuaFileStatus.MODIFIED)
        if q:
            self._file_count.set_text(f"{len(filtered)}/{total}")
        else:
            self._file_count.set_text(
                f"{total} modules  •  {modified} modified"
            )

        for i, cf in enumerate(filtered):
            if cf.filename == reselect:
                row = self._list_box.get_row_at_index(i)
                if row:
                    self._list_box.select_row(row)
                break

    def _make_row(self, cf: LuaConfigFile) -> Gtk.ListBoxRow:
        row      = Gtk.ListBoxRow()
        row._cf  = cf  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(8)
        box.set_margin_top(7)
        box.set_margin_bottom(7)

        is_modified = cf.status == LuaFileStatus.MODIFIED

        icon_name = "emblem-default-symbolic" if is_modified else "text-x-script-symbolic"
        icon = Gtk.Image.new_from_icon_name(icon_name)
        icon.set_icon_size(Gtk.IconSize.NORMAL)
        if not is_modified:
            icon.add_css_class("dim-label")

        lbl = Gtk.Label(label=cf.filename)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        from gi.repository import Pango
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        if is_modified:
            lbl.add_css_class("accent")

        badge_text = "modified" if is_modified else ("new" if cf.status == LuaFileStatus.NEW else "pristine")
        badge_css  = "hcm-badge-override" if is_modified else "hcm-badge-distro"
        badge = Gtk.Label(label=badge_text)
        badge.add_css_class("caption")
        badge.add_css_class("manager-badge")
        badge.add_css_class(badge_css)

        box.append(icon)
        box.append(lbl)
        box.append(badge)
        row.set_child(box)
        return row

    # ── Events ────────────────────────────────────────────────────────────────

    def _on_row_selected(self, _listbox: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if row is None:
            self._selected = None
            self._edit_btn.set_sensitive(False)
            return

        cf = getattr(row, "_cf", None)
        if cf is None:
            return
        self._selected = cf

        self._desc_label.set_text(cf.description)

        is_modified = cf.status == LuaFileStatus.MODIFIED
        if is_modified:
            self._status_icon.set_from_icon_name("emblem-default-symbolic")
            self._status_label.set_text("File has been modified from baseline")
            self._status_badge.set_label("modified")
            self._status_badge.remove_css_class("hcm-badge-distro")
            self._status_badge.add_css_class("hcm-badge-override")
        elif cf.status == LuaFileStatus.NEW:
            self._status_icon.set_from_icon_name("document-new-symbolic")
            self._status_label.set_text("No baseline recorded yet")
            self._status_badge.set_label("new")
            self._status_badge.remove_css_class("hcm-badge-override")
            self._status_badge.add_css_class("hcm-badge-distro")
        else:
            self._status_icon.set_from_icon_name("emblem-default-symbolic")
            self._status_label.set_text("File matches baseline")
            self._status_badge.set_label("pristine")
            self._status_badge.remove_css_class("hcm-badge-override")
            self._status_badge.add_css_class("hcm-badge-distro")

        self._edit_btn.set_sensitive(True)

        threading.Thread(
            target=self._load_preview, args=(cf,), daemon=True
        ).start()

    def _load_preview(self, cf: LuaConfigFile) -> None:
        text = _preview_lines(cf.path)
        try:
            total_lines = len(cf.path.read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError:
            total_lines = 0
        GLib.idle_add(self._apply_preview, text, cf.filename, total_lines)

    def _apply_preview(self, text: str, filename: str, line_count: int) -> bool:
        self._preview_buf.set_text(text)
        self._preview_lines_label.set_text(f"{line_count} lines  ·  {filename}")
        return GLib.SOURCE_REMOVE

    def _on_edit_clicked(self, _btn: Gtk.Button) -> None:
        if self._selected is None:
            return
        self._edit_btn.set_sensitive(False)
        threading.Thread(target=self._do_edit, args=(self._selected,), daemon=True).start()

    def _do_edit(self, cf: LuaConfigFile) -> None:
        try:
            subprocess.run(
                ["kitty", "--class", "hcm-editor",
                 "--title", f"Editing {cf.filename}",
                 "--", self._editor, str(cf.path)],
                check=False,
            )
        except FileNotFoundError:
            try:
                subprocess.run(
                    ["bash", "-c", f'{self._editor} "{cf.path}"'],
                    check=False,
                )
            except Exception as e:
                GLib.idle_add(self._edit_done, f"Editor launch failed: {e}")
                return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        GLib.idle_add(self._edit_done, f"Saved {cf.filename} — Hyprland reloaded")

    def _edit_done(self, msg: str) -> bool:
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
