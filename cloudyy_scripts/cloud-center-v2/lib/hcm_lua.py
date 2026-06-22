"""
Cloud Center — lib/hcm_lua.py
Lua config manager for ~/.config/hypr/source/*.lua and
~/.config/hypr/user-configs/user_*.lua.

The manager lists distro source modules and marks them as overridden when a
matching user module exists and hyprland.lua actively requires it.
"""
from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import threading
from dataclasses import dataclass
from enum import Enum, auto
from pathlib import Path
from typing import Optional

from gi.repository import Adw, GLib, Gtk, Pango

from lib import utility

log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────

HYPR_DIR = Path.home() / ".config" / "hypr"
SOURCE_DIR = HYPR_DIR / "source"
USER_DIR = HYPR_DIR / "user-configs"
MAIN_LUA = HYPR_DIR / "hyprland.lua"
HYPRLUA_DIR = SOURCE_DIR


# ── Data ──────────────────────────────────────────────────────────────────────

class LuaFileStatus(Enum):
    DISTRO = auto()
    USER_OVERRIDE = auto()


class LuaConfigFile:
    def __init__(self, filename: str, path: Path, description: str, status: LuaFileStatus):
        self.filename    = filename
        self.path        = path
        self.description = description
        self.status      = status


@dataclass(frozen=True)
class UserOverrideResult:
    edit_path: Path
    activated: bool
    message: str


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
#
# All persistence and activation now lives in the `hcm` Rust binary
# (~/.local/bin/hcm). These Python functions are thin wrappers that shell out
# and translate the JSON wire format back into the GTK page's existing types.

_STATUS_FROM_JSON = {
    "distro": LuaFileStatus.DISTRO,
    "user_override": LuaFileStatus.USER_OVERRIDE,
}


def _user_module_path(path: Path) -> Path:
    return USER_DIR / f"user_{path.name}"


def _preview_path_for(cf: LuaConfigFile) -> Path:
    user_path = _user_module_path(cf.path)
    if cf.status == LuaFileStatus.USER_OVERRIDE and user_path.exists():
        return user_path
    return cf.path


def hcm_json(*args: str) -> dict | list:
    """Run `hcm` and return parsed JSON stdout. Raises on non-zero exit."""
    result = subprocess.run(
        [utility.hcm_bin(), *args],
        capture_output=True,
        text=True,
        check=True,
        env=utility.command_env(),
    )
    return json.loads(result.stdout)


def switch_to_user_override(cf: LuaConfigFile) -> UserOverrideResult:
    data = hcm_json("activate", cf.path.stem)
    return UserOverrideResult(
        edit_path=Path(data["edit_path"]),
        activated=bool(data["activated"]),
        message=data["message"],
    )


def scan_lua_files() -> list[LuaConfigFile]:
    """Scan SOURCE_DIR and annotate each file as distro or user override."""
    if not SOURCE_DIR.exists():
        return []
    return [
        LuaConfigFile(
            filename=item["filename"],
            path=Path(item["path"]),
            description=item["description"],
            status=_STATUS_FROM_JSON[item["status"]],
        )
        for item in hcm_json("scan", "--json")
    ]


def revert_to_baseline(cf: LuaConfigFile) -> tuple[bool, str]:
    data = hcm_json("revert", cf.path.stem)
    return bool(data["ok"]), data["message"]


def _preview_lines(path: Path, max_lines: int = 60) -> str:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(lines[:max_lines])
    except OSError:
        return "(could not read file)"


# ── GTK4 Page ─────────────────────────────────────────────────────────────────

class LuaConfigManagerPage(Gtk.Box):
    """
    Two-panel config manager for source/*.lua modules.
    Left:  scrollable file list with distro/override badges.
    Right: description, status, preview, Edit button.
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

        self._revert_btn = Gtk.Button()
        revert_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        revert_box.append(Gtk.Image.new_from_icon_name("edit-undo-symbolic"))
        revert_box.append(Gtk.Label(label="Revert to distro"))
        self._revert_btn.set_child(revert_box)
        self._revert_btn.add_css_class("flat")
        self._revert_btn.add_css_class("destructive-action")
        self._revert_btn.set_sensitive(False)
        self._revert_btn.set_tooltip_text("Delete user override and restore distro source")
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

        total = len(self._files)
        overrides = sum(1 for cf in self._files if cf.status == LuaFileStatus.USER_OVERRIDE)
        if q:
            self._file_count.set_text(f"{len(filtered)}/{total}")
        else:
            self._file_count.set_text(
                f"{total} modules  •  {overrides} overrides"
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

        is_override = cf.status == LuaFileStatus.USER_OVERRIDE

        icon_name = "emblem-default-symbolic" if is_override else "text-x-script-symbolic"
        icon = Gtk.Image.new_from_icon_name(icon_name)
        icon.set_icon_size(Gtk.IconSize.NORMAL)
        if not is_override:
            icon.add_css_class("dim-label")
        icon.set_tooltip_text("User override active" if is_override else "Distro module active")

        lbl = Gtk.Label(label=cf.filename)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        from gi.repository import Pango
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        if is_override:
            lbl.add_css_class("accent")

        badge_text = "override" if is_override else "distro"
        badge_css = "hcm-badge-override" if is_override else "hcm-badge-distro"
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
            self._revert_btn.set_sensitive(False)
            return

        cf = getattr(row, "_cf", None)
        if cf is None:
            return
        self._selected = cf

        self._desc_label.set_text(cf.description)

        is_override = cf.status == LuaFileStatus.USER_OVERRIDE
        if is_override:
            self._status_icon.set_from_icon_name("emblem-default-symbolic")
            self._status_label.set_text("User override is active")
            self._status_badge.set_label("override")
            self._status_badge.remove_css_class("hcm-badge-distro")
            self._status_badge.add_css_class("hcm-badge-override")
        else:
            self._status_icon.set_from_icon_name("dialog-information-symbolic")
            self._status_label.set_text("Distro module is active")
            self._status_badge.set_label("distro")
            self._status_badge.remove_css_class("hcm-badge-override")
            self._status_badge.add_css_class("hcm-badge-distro")

        self._edit_btn.set_sensitive(True)
        self._revert_btn.set_sensitive(is_override)

        threading.Thread(
            target=self._load_preview, args=(cf,), daemon=True
        ).start()

    def _load_preview(self, cf: LuaConfigFile) -> None:
        path = _preview_path_for(cf)
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

    def _do_edit(self, cf: LuaConfigFile) -> None:
        try:
            result = switch_to_user_override(cf)
        except Exception as e:
            GLib.idle_add(self._edit_done, f"Failed to create user override: {e}")
            return
        edit_path = result.edit_path
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

        message = result.message
        if result.activated:
            subprocess.run(["hyprctl", "reload"], capture_output=True)
            message = f"{message} — Hyprland reloaded"
        GLib.idle_add(self._edit_done, message)

    def _edit_done(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self._edit_btn.set_sensitive(True)
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_revert_clicked(self, _btn: Gtk.Button) -> None:
        if self._selected is None or self._selected.status != LuaFileStatus.USER_OVERRIDE:
            return
        self._revert_btn.set_sensitive(False)
        self._edit_btn.set_sensitive(False)
        threading.Thread(target=self._do_revert, args=(self._selected,), daemon=True).start()

    def _do_revert(self, cf: LuaConfigFile) -> None:
        ok, msg = revert_to_baseline(cf)
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
