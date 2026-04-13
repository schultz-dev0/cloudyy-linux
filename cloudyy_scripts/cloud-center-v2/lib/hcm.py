"""
Cloud Center — lib/hcm.py
Hyprland Config Manager page, ported from the hcm Rust TUI.

Scans ~/.config/hypr/source/ for .conf files, shows distro-vs-user status,
and lets the user create user_ overrides that are sourced by hyprland.conf.
"""
from __future__ import annotations

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

# ── Paths (mirrors hcm Rust constants) ───────────────────────────────────────

HYPR_DIR        = Path.home() / ".config" / "hypr"
SOURCE_DIR      = HYPR_DIR / "source"
USER_DIR        = HYPR_DIR / "user-configs"
HYPRLAND_CONF   = HYPR_DIR / "hyprland.conf"


# ── Data ──────────────────────────────────────────────────────────────────────

class FileStatus(Enum):
    DISTRO       = auto()   # distro original, no user override active
    USER_OVERRIDE = auto()  # user copy exists and hyprland.conf points to it


class ConfigFile:
    def __init__(self, filename: str, path: Path, description: str, status: FileStatus):
        self.filename    = filename
        self.path        = path
        self.description = description
        self.status      = status


# ── Logic (ported from Rust) ──────────────────────────────────────────────────

def _active_source_paths() -> set[Path]:
    """Return canonicalized paths of every `source = …` line in hyprland.conf."""
    result: set[Path] = set()
    if not HYPRLAND_CONF.exists():
        return result
    for line in HYPRLAND_CONF.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#"):
            continue
        m = re.match(r"^\s*source\s*=\s*(.+)", line)
        if m:
            raw = m.group(1).strip()
            if raw.startswith("~"):
                raw = str(Path.home()) + raw[1:]
            p = Path(raw)
            if not p.is_absolute():
                p = HYPRLAND_CONF.parent / p
            try:
                result.add(p.resolve())
            except OSError:
                result.add(p)
    return result


def _read_description(path: Path) -> str:
    """Read the optional `#description = …` tag from the first line."""
    try:
        first = path.read_text(encoding="utf-8").splitlines()[0].strip()
        if first.startswith("#description = "):
            return first[len("#description = "):].strip()
    except (IndexError, OSError):
        pass
    return "No description available."


def scan_config_files() -> list[ConfigFile]:
    """Scan SOURCE_DIR and annotate each file as distro or user-override."""
    if not SOURCE_DIR.exists():
        return []

    active = _active_source_paths()
    files: list[ConfigFile] = []

    for p in sorted(SOURCE_DIR.iterdir()):
        if not p.is_file() or p.suffix != ".conf":
            continue

        name = p.name
        user_name = name if name.startswith("user_") else f"user_{name}"
        user_path = USER_DIR / user_name

        status = FileStatus.DISTRO
        if user_path.exists():
            try:
                if user_path.resolve() in active:
                    status = FileStatus.USER_OVERRIDE
            except OSError:
                pass

        files.append(ConfigFile(
            filename    = name,
            path        = p,
            description = _read_description(p),
            status      = status,
        ))

    return files


def switch_to_user_copy(cf: ConfigFile) -> Path:
    """
    Ensure a user-override copy of `cf` exists and that hyprland.conf sources
    it instead of the original.  Returns the path to the user copy.

    Mirrors SourceManager::switch_to_user_copy() from the Rust TUI.
    """
    user_name = (
        cf.filename if cf.filename.startswith("user_")
        else f"user_{cf.filename}"
    )
    user_path = USER_DIR / user_name
    USER_DIR.mkdir(parents=True, exist_ok=True)

    # If already active, nothing to do
    if user_path.exists() and cf.status == FileStatus.USER_OVERRIDE:
        return user_path

    # Copy original → user file if not yet present
    if not user_path.exists():
        import shutil
        shutil.copy2(cf.path, user_path)
        log.info("Created user copy: %s", user_path)

    # Rewrite the source line in hyprland.conf to point at the user copy
    _rewrite_source_line(cf.path, user_path)
    return user_path


def _rewrite_source_line(original: Path, user_copy: Path) -> None:
    """
    Replace the source = <original> line in hyprland.conf with
    source = ~/.config/hypr/user-configs/<user_copy>.
    If no existing source line is found, append one.
    """
    if not HYPRLAND_CONF.exists():
        log.warning("hyprland.conf not found — cannot rewrite source line")
        return

    content  = HYPRLAND_CONF.read_text(encoding="utf-8")
    lines    = content.splitlines(keepends=True)
    new_line = f"source = ~/.config/hypr/user-configs/{user_copy.name}\n"

    # Try to find and replace the existing source line for original or user copy
    candidates = set()
    for p in [original, user_copy]:
        try:
            candidates.add(str(p.resolve()))
        except OSError:
            pass
        candidates.add(str(p))
    # Also match tilde form
    home = str(Path.home())
    tilde_candidates = {s.replace(home, "~") for s in candidates}
    candidates |= tilde_candidates

    replaced = False
    out_lines = []
    for line in lines:
        m = re.match(r"^\s*source\s*=\s*(.+)", line.rstrip())
        if m:
            raw = m.group(1).strip()
            raw_abs = raw.replace("~", home)
            if raw in candidates or raw_abs in candidates:
                out_lines.append(new_line)
                replaced = True
                continue
        out_lines.append(line)

    if not replaced:
        # No existing line found — append
        out_lines.append(f"\n# Cloud Center — user override\n{new_line}")
        log.info("Appended source line for %s", user_copy.name)
    else:
        log.info("Rewrote source line → %s", user_copy.name)

    tmp = Path(str(HYPRLAND_CONF) + ".tmp")
    tmp.write_text("".join(out_lines), encoding="utf-8")
    tmp.replace(HYPRLAND_CONF)


def ensure_user_config_sourced(user_conf: Path) -> bool:
    """Ensure hyprland.conf sources a file from ~/.config/hypr/user-configs/."""
    try:
        _rewrite_source_line(user_conf, user_conf)
        return True
    except Exception as e:
        log.warning("Could not ensure source line for %s: %s", user_conf, e)
        return False


def revert_to_distro(cf: ConfigFile) -> tuple[bool, str]:
    """
    Delete the user override copy and rewrite hyprland.conf to source the
    original distro file again.  Returns (success, message).
    """
    user_name = (
        cf.filename if cf.filename.startswith("user_")
        else f"user_{cf.filename}"
    )
    user_path = USER_DIR / user_name

    if not user_path.exists():
        return False, "No user override found — already using distro original"

    try:
        user_path.unlink()
        log.info("Deleted user override: %s", user_path)
    except OSError as e:
        return False, f"Could not delete user copy: {e}"

    # Rewrite hyprland.conf source line back to the distro original
    try:
        _rewrite_source_line(user_path, cf.path)
    except Exception as e:
        return False, f"Deleted copy but failed to update hyprland.conf: {e}"

    return True, f"Reverted {cf.filename} to distro original"


def _preview_lines(path: Path, max_lines: int = 60) -> str:
    """Return the first max_lines of a file as a plain string."""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        return "\n".join(lines[:max_lines])
    except OSError:
        return "(could not read file)"


# ── GTK4 Page ─────────────────────────────────────────────────────────────────

class ConfigManagerPage(Gtk.Box):
    """
    Full two-panel config manager page.
    Left:  scrollable list of .conf files with distro/user-override badges.
    Right: description, status, file preview, and Edit button.
    """

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov  = toast_overlay
        self._files: list[ConfigFile] = []
        self._selected: Optional[ConfigFile] = None

        self._build_ui()
        self.refresh()

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # ── Left panel — file list ────────────────────────────────────────────
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(260, -1)

        # Header row: title + count + refresh
        list_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        list_header.set_margin_start(12)
        list_header.set_margin_end(8)
        list_header.set_margin_top(10)
        list_header.set_margin_bottom(4)

        list_title = Gtk.Label(label="Config Files")
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

        # Search entry
        self._file_search = Gtk.SearchEntry()
        self._file_search.set_placeholder_text("Filter files…")
        self._file_search.set_margin_start(8)
        self._file_search.set_margin_end(8)
        self._file_search.set_margin_bottom(6)
        self._file_search.connect("search-changed", self._on_file_search_changed)
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

        # ── Right panel — detail ──────────────────────────────────────────────
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        right.set_hexpand(True)

        # Info card — description + status badge
        info_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        info_card.add_css_class("card")
        info_card.set_margin_start(14)
        info_card.set_margin_end(14)
        info_card.set_margin_top(14)
        info_card.set_margin_bottom(8)

        self._desc_label = Gtk.Label(label="Select a file to view details.")
        self._desc_label.set_wrap(True)
        self._desc_label.set_xalign(0)
        self._desc_label.set_max_width_chars(60)

        # Status row: icon + text + badge (inline)
        status_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        status_row.set_margin_top(2)

        self._status_icon = Gtk.Image()
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

        # Action toolbar
        action_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        action_bar.set_margin_start(14)
        action_bar.set_margin_end(14)
        action_bar.set_margin_bottom(8)

        self._editor = (
            os.environ.get("EDITOR")
            or os.environ.get("VISUAL")
            or "nvim"
        )
        editor_display = Path(self._editor).name

        self._edit_btn = Gtk.Button()
        edit_btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        edit_btn_box.append(Gtk.Image.new_from_icon_name("document-edit-symbolic"))
        edit_btn_box.append(Gtk.Label(label=f"Edit in {editor_display}"))
        self._edit_btn.set_child(edit_btn_box)
        self._edit_btn.add_css_class("suggested-action")
        self._edit_btn.set_sensitive(False)
        self._edit_btn.connect("clicked", self._on_edit_clicked)

        self._revert_btn = Gtk.Button()
        revert_btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        revert_btn_box.append(Gtk.Image.new_from_icon_name("edit-undo-symbolic"))
        revert_btn_box.append(Gtk.Label(label="Revert to distro"))
        self._revert_btn.set_child(revert_btn_box)
        self._revert_btn.add_css_class("flat")
        self._revert_btn.add_css_class("destructive-action")
        self._revert_btn.set_sensitive(False)
        self._revert_btn.set_tooltip_text("Delete user override and restore distro original")
        self._revert_btn.connect("clicked", self._on_revert_clicked)

        # Spacer pushes reload to the right
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

        # Preview header with line count
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

        self._preview_buf = Gtk.TextBuffer()
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

        # ── Separator + assemble ──────────────────────────────────────────────
        vsep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.append(left)
        self.append(vsep)
        self.append(right)

    # ── Data ──────────────────────────────────────────────────────────────────

    def refresh(self) -> None:
        """Reload the file list from disk."""
        threading.Thread(target=self._do_refresh, daemon=True).start()

    def _do_refresh(self) -> None:
        files = scan_config_files()
        GLib.idle_add(self._apply_refresh, files)

    def _apply_refresh(self, files: list[ConfigFile]) -> bool:
        prev_name = self._selected.filename if self._selected else None
        self._files = files
        self._relist(prev_name)
        return GLib.SOURCE_REMOVE

    def _on_file_search_changed(self, _entry: Gtk.SearchEntry) -> None:
        self._relist(self._selected.filename if self._selected else None)

    def _relist(self, reselect_name: str | None = None) -> None:
        """Rebuild the list box, applying the search filter."""
        q = self._file_search.get_text().strip().lower()
        filtered = [
            cf for cf in self._files
            if not q or q in cf.filename.lower() or q in cf.description.lower()
        ]

        while row := self._list_box.get_row_at_index(0):
            self._list_box.remove(row)

        for cf in filtered:
            self._list_box.append(self._make_file_row(cf))

        # Update count label
        total = len(self._files)
        overrides = sum(1 for cf in self._files if cf.status == FileStatus.USER_OVERRIDE)
        if q:
            self._file_count.set_text(f"{len(filtered)}/{total}")
        else:
            self._file_count.set_text(
                f"{total} files  •  {overrides} override{'s' if overrides != 1 else ''}"
            )

        # Re-select previously selected file if still present
        for i, cf in enumerate(filtered):
            if cf.filename == reselect_name:
                row = self._list_box.get_row_at_index(i)
                if row:
                    self._list_box.select_row(row)
                break

        if not self._files:
            self._desc_label.set_text(
                f"No .conf files found in {SOURCE_DIR}\n"
                "Make sure your Hyprland config uses a source/ directory."
            )

    def _make_file_row(self, cf: ConfigFile) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._cf = cf  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(8)
        box.set_margin_top(7)
        box.set_margin_bottom(7)

        is_override = cf.status == FileStatus.USER_OVERRIDE

        # Status icon
        icon_name = "emblem-default-symbolic" if is_override else "text-x-generic-symbolic"
        icon = Gtk.Image.new_from_icon_name(icon_name)
        icon.set_icon_size(Gtk.IconSize.NORMAL)
        if not is_override:
            icon.add_css_class("dim-label")
        icon.set_tooltip_text(
            "User override active" if is_override else "Distro original"
        )

        # Filename label
        lbl = Gtk.Label(label=cf.filename)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        if is_override:
            lbl.add_css_class("accent")

        # Styled badge
        badge_text = "override" if is_override else "distro"
        badge = Gtk.Label(label=badge_text)
        badge.add_css_class("caption")
        badge.add_css_class("manager-badge")
        badge.add_css_class("hcm-badge-override" if is_override else "hcm-badge-distro")

        box.append(icon)
        box.append(lbl)
        box.append(badge)
        row.set_child(box)
        return row

    # ── Events ────────────────────────────────────────────────────────────────

    def _on_row_selected(self, listbox: Gtk.ListBox, row: Gtk.ListBoxRow) -> None:
        if row is None:
            self._selected = None
            self._edit_btn.set_sensitive(False)
            self._revert_btn.set_sensitive(False)
            return

        cf = getattr(row, "_cf", None)
        if cf is None:
            return
        self._selected = cf

        # Update description
        self._desc_label.set_text(cf.description)

        # Status: icon + text + badge (no emoji)
        is_override = cf.status == FileStatus.USER_OVERRIDE
        if is_override:
            self._status_icon.set_from_icon_name("emblem-default-symbolic")
            self._status_icon.remove_css_class("hcm-status-distro")
            self._status_icon.add_css_class("hcm-status-override")
            self._status_label.set_text("User override is active")
            self._status_label.remove_css_class("hcm-status-distro")
            self._status_label.add_css_class("hcm-status-override")
            self._status_badge.set_label("override")
            for cls in ("hcm-badge-distro",):
                self._status_badge.remove_css_class(cls)
            self._status_badge.add_css_class("hcm-badge-override")
        else:
            self._status_icon.set_from_icon_name("dialog-information-symbolic")
            self._status_icon.remove_css_class("hcm-status-override")
            self._status_icon.add_css_class("hcm-status-distro")
            self._status_label.set_text("Distro original — edit to create a user copy")
            self._status_label.remove_css_class("hcm-status-override")
            self._status_label.add_css_class("hcm-status-distro")
            self._status_badge.set_label("distro")
            self._status_badge.remove_css_class("hcm-badge-override")
            self._status_badge.add_css_class("hcm-badge-distro")

        self._edit_btn.set_sensitive(True)
        self._revert_btn.set_sensitive(is_override)

        # Update preview (read in thread to avoid blocking UI)
        threading.Thread(
            target=self._load_preview, args=(cf,), daemon=True
        ).start()

    def _load_preview(self, cf: ConfigFile) -> None:
        # Show the user copy if it exists, otherwise the original
        user_path = USER_DIR / (
            cf.filename if cf.filename.startswith("user_")
            else f"user_{cf.filename}"
        )
        path = user_path if user_path.exists() else cf.path
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
        cf = self._selected
        self._edit_btn.set_sensitive(False)

        threading.Thread(
            target=self._do_edit, args=(cf,), daemon=True
        ).start()

    def _do_edit(self, cf: ConfigFile) -> None:
        try:
            user_path = switch_to_user_copy(cf)
        except Exception as e:
            GLib.idle_add(self._edit_done, None, f"Failed to create user copy: {e}")
            return

        editor = self._editor

        try:
            # Open in a floating kitty window; wait for it to close
            subprocess.run(
                ["kitty", "--class", "hcm-editor",
                 "--title", f"Editing {user_path.name}",
                 "--", editor, str(user_path)],
                check=False,
            )
        except FileNotFoundError:
            # kitty not found — try running editor directly in a terminal
            try:
                subprocess.run(
                    ["bash", "-c",
                     f'$EDITOR "{user_path}" || nvim "{user_path}"'],
                    check=False,
                )
            except Exception as e:
                GLib.idle_add(self._edit_done, None, f"Editor launch failed: {e}")
                return

        # Reload Hyprland after editing
        subprocess.run(
            ["hyprctl", "reload"],
            capture_output=True,
        )

        GLib.idle_add(self._edit_done, cf, f"Saved {user_path.name} — Hyprland reloaded")

    def _edit_done(self, cf: Optional[ConfigFile], msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self._edit_btn.set_sensitive(True)
        # Refresh list so badges update
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_revert_clicked(self, _btn: Gtk.Button) -> None:
        if self._selected is None or self._selected.status != FileStatus.USER_OVERRIDE:
            return
        self._revert_btn.set_sensitive(False)
        self._edit_btn.set_sensitive(False)
        threading.Thread(
            target=self._do_revert, args=(self._selected,), daemon=True
        ).start()

    def _do_revert(self, cf: ConfigFile) -> None:
        from lib import utility
        ok, msg = revert_to_distro(cf)
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