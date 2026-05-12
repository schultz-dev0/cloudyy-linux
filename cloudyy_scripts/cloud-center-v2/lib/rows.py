"""
Cloud Center — lib/rows.py
Native GTK4/Libadwaita row widgets driven by config.yaml.
Supports both GTK symbolic icon names and Nerd Font glyph characters.
"""
from __future__ import annotations

import logging
import os
import threading
from pathlib import Path
from typing import Any

import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Adw, GLib, GdkPixbuf, Gtk

import lib.utility as utility
import lib.wallpaper_browser as wallpaper_browser
import lib.extension_browser as extension_browser

log = logging.getLogger(__name__)


# ── Nerd Font / icon helper ───────────────────────────────────────────────────

def _make_prefix_icon(icon_name: str) -> Gtk.Widget:
    """
    Return a Gtk.Image for GTK symbolic icon names, or a Gtk.Label for
    Nerd Font glyphs (detected by the presence of any non-ASCII codepoint).
    """
    if not icon_name:
        return Gtk.Box()
    if any(ord(c) > 127 for c in icon_name):
        lbl = Gtk.Label(label=icon_name)
        lbl.add_css_class("nerd-icon")
        lbl.add_css_class("row-nerd-icon")
        return lbl
    return Gtk.Image.new_from_icon_name(icon_name)


# ── Shared context passed to every row ───────────────────────────────────────

class RowContext:
    def __init__(self, toast_overlay: Adw.ToastOverlay):
        self.toast_overlay = toast_overlay

    def toast(self, msg: str) -> None:
        utility.toast(self.toast_overlay, msg)


# ── Base widget lifecycle helper ──────────────────────────────────────────────

class _ManagedRow:
    """Mixin that tracks GLib source IDs and cancels them on unroot."""

    def _init_sources(self) -> None:
        self._sources: list[int] = []
        self._destroyed = False
        self._lock = threading.Lock()

    def _add_source(self, sid: int) -> None:
        with self._lock:
            if not self._destroyed:
                self._sources.append(sid)

    def _cleanup(self) -> None:
        with self._lock:
            self._destroyed = True
            sources, self._sources = self._sources, []
        for sid in sources:
            GLib.source_remove(sid)


# ── Button row ────────────────────────────────────────────────────────────────

class ButtonRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCButtonRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._props = props
        self._action = action or {}
        self._ctx = ctx

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))
        self.set_activatable(True)

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        btn_label = props.get("button_text", "")
        if btn_label:
            btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER)
            btn.add_css_class("flat")
            btn.connect("clicked", self._on_activate)
            self.add_suffix(btn)
        else:
            chevron = Gtk.Image.new_from_icon_name("go-next-symbolic")
            self.add_suffix(chevron)

        self.connect("activated", self._on_activate)

    def _on_activate(self, *_) -> None:
        # Special built-in actions
        action_id = self._props.get("action", "")
        if action_id == "bezier_editor":
            self._open_bezier_editor()
            return

        cmd = self._action.get("command", "")
        terminal = bool(self._action.get("terminal", False))
        if cmd:
            ok = utility.execute_command(cmd, terminal=terminal)
            self._ctx.toast(" Launched" if ok else " Failed")

    def _open_bezier_editor(self) -> None:
        try:
            from lib.bezier_editor import BezierEditorDialog
        except Exception as exc:
            self._ctx.toast(f"Bezier editor unavailable: {exc}")
            return
        root = self.get_root()
        if root is None:
            self._ctx.toast("No parent window")
            return
        dialog = BezierEditorDialog(root)
        dialog.present(root)

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleManager(_ManagedRow):
    """Manages state polling and command dispatch for an Adw.SwitchRow."""

    def __init__(self, row: Adw.SwitchRow, props: dict, action: dict, ctx: RowContext) -> None:
        self._init_sources()
        self._row = row
        self._action = action
        self._ctx = ctx
        self._key = props.get("key", "")
        self._state_cmd = props.get("state_command", "")
        self._interval = int(props.get("interval", 5))

        if self._key:
            row.set_active(utility.load_setting(self._key, False))

        self._handler_id = row.connect("notify::active", self._on_toggle)
        row.connect("destroy", lambda _: self._cleanup())

        if self._state_cmd:
            self._poll_state()
            sid = GLib.timeout_add_seconds(self._interval, self._poll_state)
            self._add_source(sid)

    def _poll_state(self) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE
        threading.Thread(target=self._fetch_state, daemon=True).start()
        return GLib.SOURCE_CONTINUE

    def _fetch_state(self) -> None:
        import subprocess
        try:
            r = subprocess.run(
                ["bash", "-c", self._state_cmd],
                capture_output=True, text=True, timeout=5
            )
            out = r.stdout.strip().lower()
            active = (
                out in {"yes", "true", "1", "on", "enabled", "active", "running"}
                or (out.isdigit() and int(out) > 0)
            )
            GLib.idle_add(self._apply_state, active)
        except Exception:
            pass

    def _apply_state(self, active: bool) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE
        self._row.handler_block(self._handler_id)
        self._row.set_active(active)
        self._row.handler_unblock(self._handler_id)
        return GLib.SOURCE_REMOVE

    def _on_toggle(self, row: Adw.SwitchRow, _param: object) -> None:
        state = row.get_active()
        key = "enabled" if state else "disabled"
        act = self._action.get(key, {})
        if cmd := act.get("command", ""):
            utility.execute_command(cmd, terminal=bool(act.get("terminal", False)))
        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, state), daemon=True
            ).start()


def ToggleRow(props: dict, action: dict | None, ctx: RowContext) -> Adw.SwitchRow:
    """Return a configured Adw.SwitchRow with state polling and command dispatch."""
    row = Adw.SwitchRow()
    row.set_title(props.get("title", ""))
    row.set_subtitle(props.get("description", ""))
    if icon := props.get("icon"):
        row.add_prefix(_make_prefix_icon(icon))
    # Keep manager alive by attaching it to the row object
    row._cc_manager = _ToggleManager(row, props, action or {}, ctx)  # type: ignore[attr-defined]
    return row


# ── Slider row ────────────────────────────────────────────────────────────────

class SliderRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCSliderRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._debounce_sid: int = 0
        self._cmd_template: str = action.get("command", "") if action else ""

        mn   = float(props.get("min",  0))
        mx   = float(props.get("max",  100))
        step = float(props.get("step", 1))
        default = float(props.get("default", mn))

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, mn, mx, step)
        scale.set_hexpand(True)
        scale.set_size_request(160, -1)
        scale.set_draw_value(True)
        scale.set_valign(Gtk.Align.CENTER)

        if self._key:
            scale.set_value(utility.load_setting(self._key, default))
        else:
            scale.set_value(default)

        scale.connect("value-changed", self._on_change)
        self.add_suffix(scale)
        self._scale = scale

    def _on_change(self, scale: Gtk.Scale) -> None:
        if self._debounce_sid:
            GLib.source_remove(self._debounce_sid)
        self._debounce_sid = GLib.timeout_add(150, self._apply, scale.get_value())

    def _apply(self, value: float) -> bool:
        self._debounce_sid = 0
        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, value), daemon=True
            ).start()
        if self._cmd_template:
            # Keep integer-like values compact, but preserve decimals for fine sliders.
            if float(value).is_integer():
                value_text = str(int(value))
            else:
                value_text = f"{value:.3f}".rstrip("0").rstrip(".")
            cmd = (
                self._cmd_template
                .replace("{value}", value_text)
                .replace("{value_i}", str(int(round(value))))
                .replace("{value_f}", f"{value:.2f}")
            )
            utility.execute_command(cmd)
        return GLib.SOURCE_REMOVE

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Selection (combo) row ─────────────────────────────────────────────────────

class SelectionRow(Adw.ComboRow, _ManagedRow):
    __gtype_name__ = "CCSelectionRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._options = props.get("options", [])
        self._options_map = props.get("options_map", {})
        self._cmd_template: str = action.get("command", "") if action else ""

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        store = Gtk.StringList.new(self._options)
        self.set_model(store)

        saved = utility.load_setting(self._key, "") if self._key else ""
        if saved in self._options:
            self.set_selected(self._options.index(saved))

        self.connect("notify::selected", self._on_change)

    def _on_change(self, *_) -> None:
        idx = self.get_selected()
        if idx >= len(self._options):
            return
        value = self._options[idx]
        mapped = self._options_map.get(value, value)

        # YAML mappings may provide ints/bools; command templates need strings.
        if isinstance(mapped, bool):
            mapped_text = "true" if mapped else "false"
        else:
            mapped_text = str(mapped)
        value_text = str(value)

        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, value), daemon=True
            ).start()

        if self._cmd_template:
            cmd = self._cmd_template.replace("{value}", mapped_text).replace("{option}", value_text)
            utility.execute_command(cmd)

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ComboRow.do_unroot(self)


class MultiSelectionRow(Adw.ExpanderRow, _ManagedRow):
    __gtype_name__ = "CCMultiSelectionRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._options = props.get("options", [])
        self._options_map = props.get("options_map", {})
        self._cmd_template: str = self._action.get("command", "")
        self._selected_set: set[str] = set()
        self._switches: dict[str, Adw.SwitchRow] = {}
        self._updating = False

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        self.set_show_enable_switch(False)

        saved_raw = utility.load_setting(self._key, "") if self._key else ""
        self._selected_set = self._parse_saved_values(saved_raw)

        if not self._selected_set and self._options:
            self._selected_set.add(str(self._options[0]))

        for option in self._options:
            opt = str(option)
            sw = Adw.SwitchRow()
            sw.set_title(opt)
            sw.set_active(opt in self._selected_set)
            sw.connect("notify::active", self._on_toggle, opt)
            self._switches[opt] = sw
            self.add_row(sw)

        self._update_summary_subtitle()

    def _parse_saved_values(self, saved_raw: Any) -> set[str]:
        if isinstance(saved_raw, list):
            parsed = {str(v).strip() for v in saved_raw if str(v).strip()}
        else:
            parsed = {
                part.strip()
                for part in str(saved_raw).split(",")
                if part.strip()
            }
        return {v for v in parsed if v in {str(o) for o in self._options}}

    def _selected_in_order(self) -> list[str]:
        return [str(o) for o in self._options if str(o) in self._selected_set]

    def _mapped_selected_text(self) -> str:
        mapped: list[str] = []
        for value in self._selected_in_order():
            mv = self._options_map.get(value, value)
            if isinstance(mv, bool):
                mapped.append("true" if mv else "false")
            else:
                mapped.append(str(mv))
        return ",".join(mapped)

    def _selected_text(self) -> str:
        return ",".join(self._selected_in_order())

    def _update_summary_subtitle(self) -> None:
        selected = self._selected_in_order()
        if not selected:
            self.set_subtitle("No selection")
            return
        if len(selected) <= 4:
            self.set_subtitle(", ".join(selected))
            return
        self.set_subtitle(f"{', '.join(selected[:4])} +{len(selected) - 4} more")

    def _persist_and_apply(self) -> None:
        selected_text = self._selected_text()
        mapped_text = self._mapped_selected_text()

        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, selected_text), daemon=True
            ).start()

        if self._cmd_template:
            cmd = (
                self._cmd_template
                .replace("{value}", mapped_text)
                .replace("{option}", selected_text)
            )
            utility.execute_command(cmd)

        self._update_summary_subtitle()

    def _on_toggle(self, row: Adw.SwitchRow, _param: object, option: str) -> None:
        if self._updating:
            return

        active = row.get_active()
        if active:
            self._selected_set.add(option)
            self._persist_and_apply()
            return

        if option in self._selected_set:
            if len(self._selected_set) == 1:
                self._updating = True
                row.set_active(True)
                self._updating = False
                self._ctx.toast("At least one layout must stay enabled")
                return
            self._selected_set.remove(option)
            self._persist_and_apply()

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ExpanderRow.do_unroot(self)


# ── Label (info display) row ──────────────────────────────────────────────────

class LabelRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCLabelRow"

    def __init__(self, props: dict, value_cfg: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._ctx = ctx
        self._value_cfg = value_cfg or {}

        self.set_title(props.get("title", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        self._label = Gtk.Label(label="…", valign=Gtk.Align.CENTER)
        self._label.add_css_class("dim-label")
        self._label.set_single_line_mode(True)
        self._label.set_wrap(False)
        self._label.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        self._label.set_max_width_chars(40)
        self.add_suffix(self._label)

        self._refresh()
        interval = int(props.get("interval", 0))
        if interval > 0:
            sid = GLib.timeout_add_seconds(interval, self._refresh)
            self._add_source(sid)

    def _refresh(self) -> bool:
        vtype = self._value_cfg.get("type", "")
        match vtype:
            case "system":
                val = utility.get_system_info(self._value_cfg.get("key", ""))
                self._label.set_label(val)
            case "exec":
                cmd = self._value_cfg.get("command", "")
                threading.Thread(target=self._exec_value, args=(cmd,), daemon=True).start()
            case "static":
                self._label.set_label(str(self._value_cfg.get("text", "")))
        return GLib.SOURCE_CONTINUE

    def _exec_value(self, cmd: str) -> None:
        import subprocess
        try:
            r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=5)
            val = r.stdout.strip() or "N/A"
        except Exception:
            val = "Error"
        GLib.idle_add(self._label.set_label, val)

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Wallpaper picker ──────────────────────────────────────────────────────────

_WALL_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
_THEME_STATE = Path.home() / ".config" / "hypr" / "theme_state" / "state.conf"
_THUMB_SEMA = threading.BoundedSemaphore(6)


def _read_current_wallpaper() -> str:
    """Parse CURRENT_WALL from theme_state/state.conf."""
    try:
        for line in _THEME_STATE.read_text(encoding="utf-8").splitlines():
            if line.startswith("CURRENT_WALL="):
                val = line[len("CURRENT_WALL="):].strip().strip('"\'')
                return val
    except (FileNotFoundError, OSError):
        pass
    return ""


def _read_theme_mode() -> str:
    """Read THEME_MODE from theme state, fallback to cloud-center setting."""
    try:
        for line in _THEME_STATE.read_text(encoding="utf-8").splitlines():
            if line.startswith("THEME_MODE="):
                val = line[len("THEME_MODE="):].strip().strip('"\'').lower()
                if val in {"light", "dark"}:
                    return val
    except (FileNotFoundError, OSError):
        pass

    try:
        return "dark" if utility.load_setting("theme/dark_mode", False) else "light"
    except Exception:
        return "dark"


class WallpaperPickerRow(Adw.PreferencesRow, _ManagedRow):
    """A visual wallpaper grid that mimics waypaper, embedded as a preferences row."""

    __gtype_name__ = "CCWallpaperPickerRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "wallpaper/current")
        raw_dir = props.get("directory", "~/Wallpapers")
        self._directory = Path(os.path.expandvars(raw_dir)).expanduser()
        self._thumb_size = int(props.get("thumbnail_size", 160))
        self._columns = int(props.get("columns", 0))  # 0 = auto
        self._max_items = int(props.get("max_items", 100))
        self._cmd_template = (
            self._action.get("command", "")
            or "~/cloudyy_scripts/theme_controller.sh set-image {path}"
        )
        self._current_path = _read_current_wallpaper()
        self._buttons: dict[str, Gtk.Button] = {}

        self.set_activatable(False)
        self._build_widget(props)

    def _build_widget(self, props: dict) -> None:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.add_css_class("wallpaper-picker-box")
        self._outer = outer
        self._empty_label: Gtk.Label | None = None

        # ── Header row ────────────────────────────────────────────────────────
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        header.add_css_class("wallpaper-picker-header")
        header.set_margin_start(12)
        header.set_margin_end(12)
        header.set_margin_top(10)
        header.set_margin_bottom(6)

        if icon := props.get("icon"):
            icon_w = _make_prefix_icon(icon)
            header.append(icon_w)

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)

        title_lbl = Gtk.Label(label=props.get("title", "Wallpaper"), xalign=0)
        title_lbl.add_css_class("wallpaper-picker-title")
        title_box.append(title_lbl)

        if desc := props.get("description"):
            desc_lbl = Gtk.Label(label=desc, xalign=0)
            desc_lbl.add_css_class("wallpaper-picker-desc")
            desc_lbl.add_css_class("dim-label")
            title_box.append(desc_lbl)

        header.append(title_box)

        self._current_label = Gtk.Label(label="", xalign=1)
        self._current_label.add_css_class("wallpaper-current-name")
        self._current_label.add_css_class("dim-label")
        self._current_label.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        self._current_label.set_max_width_chars(28)
        if self._current_path:
            self._current_label.set_label(Path(self._current_path).name)
        header.append(self._current_label)

        outer.append(header)

        # ── Separator ─────────────────────────────────────────────────────────
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        outer.append(sep)

        # ── Spinner shown while loading ───────────────────────────────────────
        self._spinner = Gtk.Spinner()
        self._spinner.set_spinning(True)
        self._spinner.set_margin_top(24)
        self._spinner.set_margin_bottom(24)
        self._spinner.set_halign(Gtk.Align.CENTER)
        outer.append(self._spinner)

        # ── Scrolled FlowBox ──────────────────────────────────────────────────
        self._flow = Gtk.FlowBox()
        self._flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self._flow.set_homogeneous(True)
        self._flow.set_row_spacing(8)
        self._flow.set_column_spacing(8)
        self._flow.add_css_class("wallpaper-grid")
        if self._columns > 0:
            self._flow.set_min_children_per_line(self._columns)
            self._flow.set_max_children_per_line(self._columns)
        else:
            self._flow.set_max_children_per_line(20)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        rows_shown = int(props.get("rows", 4))
        row_h = self._thumb_size + 8  # thumb + row_spacing
        scroll.set_min_content_height(row_h * rows_shown + 16)
        scroll.set_max_content_height(row_h * rows_shown + 16)
        scroll.set_child(self._flow)
        scroll.add_css_class("wallpaper-scroll")
        scroll.set_margin_start(10)
        scroll.set_margin_end(10)
        scroll.set_margin_top(8)
        scroll.set_margin_bottom(10)

        outer.append(scroll)
        self.set_child(outer)

        # Load thumbnails in background thread
        threading.Thread(target=self._load_thumbnails, daemon=True).start()

    def _load_thumbnails(self) -> None:
        """Collect image paths and schedule grid population on main thread."""
        try:
            base = self._directory
            if not base.exists():
                # Fallback to the online browser default when the old path was moved.
                base = Path("~/Wallpapers/Online").expanduser()

            # Mirror theme_controller.sh behavior: prefer mode-specific dir if present.
            mode = _read_theme_mode()
            mode_dir = base / mode.capitalize()
            if mode_dir.is_dir():
                scan_root = mode_dir
                use_recursive = True
            else:
                scan_root = base
                use_recursive = False

            if use_recursive:
                paths = [
                    p for p in scan_root.rglob("*")
                    if p.is_file() and p.suffix.lower() in _WALL_EXTS
                ]
            else:
                # Stay shallow in flat dir so Light/ and Dark/ siblings are not mixed.
                paths = [
                    p for p in scan_root.iterdir()
                    if p.is_file() and p.suffix.lower() in _WALL_EXTS
                ]

            paths.sort(key=lambda p: p.stat().st_mtime, reverse=True)
            paths = paths[: self._max_items]
            self._directory = scan_root
        except Exception as exc:
            log.warning("WallpaperPicker: cannot list %s: %s", self._directory, exc)
            paths = []
        GLib.idle_add(self._populate_grid, paths)

    def _populate_grid(self, paths: list[Path]) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE

        # Remove spinner
        parent = self._spinner.get_parent()
        if parent:
            parent.remove(self._spinner)

        # Remove any previous empty-state label when repopulating.
        if self._empty_label is not None and self._empty_label.get_parent() is self._outer:
            self._outer.remove(self._empty_label)
            self._empty_label = None

        if not paths:
            empty = Gtk.Label(label=f"No wallpapers found in\n{self._directory}")
            empty.add_css_class("dim-label")
            empty.set_margin_top(16)
            empty.set_margin_bottom(16)
            self._outer.append(empty)
            self._empty_label = empty
            return GLib.SOURCE_REMOVE

        # Load each thumbnail in its own thread to avoid blocking UI
        for path in paths:
            threading.Thread(
                target=self._load_one_thumb,
                args=(path,),
                daemon=True,
            ).start()

        return GLib.SOURCE_REMOVE

    def _load_one_thumb(self, path: Path) -> None:
        """Load a scaled pixbuf in a worker thread, then add button on main thread."""
        if not _THUMB_SEMA.acquire(timeout=3):
            return
        try:
            with self._lock:
                if self._destroyed:
                    return
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                str(path), self._thumb_size, self._thumb_size, True
            )
        except Exception as exc:
            log.debug("WallpaperPicker: skip %s: %s", path.name, exc)
            return
        finally:
            _THUMB_SEMA.release()
        GLib.idle_add(self._add_thumbnail, path, pixbuf)

    def _add_thumbnail(self, path: Path, pixbuf: GdkPixbuf.Pixbuf) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE

        # Build thumbnail button
        img = Gtk.Picture.new_for_pixbuf(pixbuf)
        img.set_content_fit(Gtk.ContentFit.COVER)
        img.set_size_request(self._thumb_size, self._thumb_size)

        overlay = Gtk.Overlay()
        overlay.set_child(img)

        # Check mark overlay for current wallpaper
        check = Gtk.Image.new_from_icon_name("object-select-symbolic")
        check.add_css_class("wallpaper-check")
        check.set_halign(Gtk.Align.END)
        check.set_valign(Gtk.Align.START)
        overlay.add_overlay(check)
        check.set_visible(str(path) == self._current_path)

        btn = Gtk.Button()
        btn.set_child(overlay)
        btn.add_css_class("wallpaper-thumb-btn")
        btn.set_tooltip_text(path.name)
        if str(path) == self._current_path:
            btn.add_css_class("wallpaper-thumb-active")

        btn.connect("clicked", self._on_select, path, check)
        self._buttons[str(path)] = (btn, check)
        self._flow.append(btn)
        return GLib.SOURCE_REMOVE

    def _on_select(self, _btn: Gtk.Button, path: Path, _check: Gtk.Image) -> None:
        # Deactivate previous
        if self._current_path and self._current_path in self._buttons:
            old_btn, old_check = self._buttons[self._current_path]
            old_btn.remove_css_class("wallpaper-thumb-active")
            old_check.set_visible(False)

        self._current_path = str(path)

        if self._key:
            threading.Thread(
                target=utility.save_setting,
                args=(self._key, str(path)),
                daemon=True,
            ).start()

        # Activate new
        new_btn, new_check = self._buttons[str(path)]
        new_btn.add_css_class("wallpaper-thumb-active")
        new_check.set_visible(True)
        self._current_label.set_label(path.name)

        # Run command
        cmd = self._cmd_template.replace("{path}", str(path))
        ok = utility.execute_command(cmd)
        self._ctx.toast(f"󱉟 {path.name}" if ok else " Failed to apply wallpaper")

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.PreferencesRow.do_unroot(self)


# ── Row factory ───────────────────────────────────────────────────────────────

def build_row(item: dict, ctx: RowContext) -> Gtk.Widget | None:
    itype = item.get("type", "")
    props = item.get("properties", {})
    try:
        match itype:
            case "button":
                return ButtonRow(props, item.get("on_press"), ctx)
            case "toggle":
                return ToggleRow(props, item.get("on_toggle"), ctx)
            case "slider":
                return SliderRow(props, item.get("on_change"), ctx)
            case "selection":
                return SelectionRow(props, item.get("on_change"), ctx)
            case "multi_selection":
                return MultiSelectionRow(props, item.get("on_change"), ctx)
            case "label":
                return LabelRow(props, item.get("value"), ctx)
            case "wallpaper_picker":
                return WallpaperPickerRow(props, item.get("on_select"), ctx)
            case "online_wallpaper_browser":
                return wallpaper_browser.OnlineWallpaperBrowserRow(props, item.get("on_search"), ctx)
            case "extension_browser":
                return extension_browser.ExtensionBrowserRow(props, item.get("on_action"), ctx)
            case _:
                log.warning("Unknown row type: %s", itype)
                return None
    except Exception as e:
        log.error("Failed to build row type=%s: %s", itype, e)
        err = Adw.ActionRow(title=f" {props.get('title','?')}", subtitle=str(e)[:80])
        err.add_css_class("error")
        return err