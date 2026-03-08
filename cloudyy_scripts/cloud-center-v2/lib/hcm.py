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

        list_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        list_header.set_margin_start(12)
        list_header.set_margin_end(12)
        list_header.set_margin_top(12)
        list_header.set_margin_bottom(6)

        list_title = Gtk.Label(label="Config Files")
        list_title.add_css_class("heading")
        list_title.set_hexpand(True)
        list_title.set_xalign(0)

        refresh_btn = Gtk.Button()
        refresh_btn.set_icon_name("view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Reload file list")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        list_header.append(list_title)
        list_header.append(refresh_btn)
        left.append(list_header)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        left.append(sep)

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

        # Description card
        desc_frame = Gtk.Frame()
        desc_frame.set_margin_start(16)
        desc_frame.set_margin_end(16)
        desc_frame.set_margin_top(16)
        desc_frame.set_margin_bottom(8)

        desc_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        desc_inner.set_margin_start(12)
        desc_inner.set_margin_end(12)
        desc_inner.set_margin_top(10)
        desc_inner.set_margin_bottom(10)

        self._desc_label = Gtk.Label(label="Select a file to view details.")
        self._desc_label.set_wrap(True)
        self._desc_label.set_xalign(0)
        self._desc_label.set_max_width_chars(60)

        self._status_label = Gtk.Label()
        self._status_label.set_xalign(0)
        self._status_label.add_css_class("dim-label")
        self._status_label.set_margin_top(4)

        desc_inner.append(self._desc_label)
        desc_inner.append(self._status_label)
        desc_frame.set_child(desc_inner)
        right.append(desc_frame)

        # Action row
        action_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        action_row.set_margin_start(16)
        action_row.set_margin_end(16)
        action_row.set_margin_bottom(8)

        self._editor = (
            os.environ.get("EDITOR")
            or os.environ.get("VISUAL")
            or "nvim"
        )
        editor_display = Path(self._editor).name  # strip any path prefix
        self._edit_btn = Gtk.Button(label=f"Edit in {editor_display}")
        self._edit_btn.add_css_class("suggested-action")
        self._edit_btn.set_sensitive(False)
        self._edit_btn.connect("clicked", self._on_edit_clicked)

        self._reload_btn = Gtk.Button(label="Reload Hyprland")
        self._reload_btn.add_css_class("flat")
        self._reload_btn.connect("clicked", self._on_reload_clicked)

        action_row.append(self._edit_btn)
        action_row.append(self._reload_btn)
        right.append(action_row)

        # Preview
        preview_label = Gtk.Label(label="Preview")
        preview_label.add_css_class("heading")
        preview_label.set_xalign(0)
        preview_label.set_margin_start(16)
        preview_label.set_margin_bottom(4)
        right.append(preview_label)

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
        preview_scroll.set_margin_start(16)
        preview_scroll.set_margin_end(16)
        preview_scroll.set_margin_bottom(16)
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

        # Rebuild list rows
        while row := self._list_box.get_row_at_index(0):
            self._list_box.remove(row)

        for cf in files:
            self._list_box.append(self._make_file_row(cf))

        # Re-select previously selected file if still present
        for i, cf in enumerate(self._files):
            if cf.filename == prev_name:
                row = self._list_box.get_row_at_index(i)
                if row:
                    self._list_box.select_row(row)
                break

        if not self._files:
            self._desc_label.set_text(
                f"No .conf files found in {SOURCE_DIR}\n"
                "Make sure your Hyprland config uses a source/ directory."
            )

        return GLib.SOURCE_REMOVE

    def _make_file_row(self, cf: ConfigFile) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._cf = cf  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_margin_start(12)
        box.set_margin_end(8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        # Status icon
        if cf.status == FileStatus.USER_OVERRIDE:
            icon = Gtk.Image.new_from_icon_name("emblem-default-symbolic")
            icon.set_tooltip_text("User override active")
        else:
            icon = Gtk.Image.new_from_icon_name("document-edit-symbolic")
            icon.add_css_class("dim-label")
            icon.set_tooltip_text("Distro original")

        # Filename label
        lbl = Gtk.Label(label=cf.filename)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        lbl.set_ellipsize(Pango.EllipsizeMode.END)
        if cf.status == FileStatus.USER_OVERRIDE:
            lbl.add_css_class("accent")

        # Badge
        badge = Gtk.Label(
            label="override" if cf.status == FileStatus.USER_OVERRIDE else "distro"
        )
        badge.add_css_class("caption")
        badge.add_css_class("dim-label")

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
            return

        cf = getattr(row, "_cf", None)
        if cf is None:
            return
        self._selected = cf

        # Update description
        self._desc_label.set_text(cf.description)

        if cf.status == FileStatus.USER_OVERRIDE:
            self._status_label.set_text("✎  user override active")
        else:
            self._status_label.set_text("  distro original — editing will create a user copy")

        # Update preview (read in thread to avoid blocking UI)
        self._edit_btn.set_sensitive(True)
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
        GLib.idle_add(self._apply_preview, text, path.name)

    def _apply_preview(self, text: str, filename: str) -> bool:
        self._preview_buf.set_text(text)
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

    def _on_reload_clicked(self, _btn: Gtk.Button) -> None:
        from lib import utility
        threading.Thread(
            target=lambda: subprocess.run(["hyprctl", "reload"], capture_output=True),
            daemon=True,
        ).start()
        utility.toast(self._toast_ov, "Hyprland reloading…")