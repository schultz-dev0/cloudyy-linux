"""Cloud Center — Cursor settings page."""

from __future__ import annotations

import subprocess
import threading
from pathlib import Path

from gi.repository import Adw, Gtk

import lib.utility as utility

PERSIST = str(Path(__file__).resolve().parents[1] / "hypr_persist.sh")


def _run(cmd: str) -> None:
    utility.execute_command(cmd)


def _save(key: str, value: object) -> None:
    threading.Thread(
        target=utility.save_setting, args=(key, value), daemon=True
    ).start()


def _load(key: str, default: object) -> object:
    return utility.load_setting(key, default)


def _get_cursor_themes() -> list[str]:
    dirs = [
        Path("/usr/share/icons"),
        Path.home() / ".local/share/icons",
        Path.home() / ".icons",
    ]
    themes: set[str] = set()
    for d in dirs:
        if d.is_dir():
            for entry in d.iterdir():
                if entry.is_dir() and (entry / "cursors").is_dir():
                    themes.add(entry.name)
    return sorted(themes) or ["Adwaita"]


def _gsettings_get(key: str, fallback: str) -> str:
    try:
        r = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", key],
            capture_output=True,
            text=True,
            timeout=3,
        )
        val = r.stdout.strip().strip("'\"")
        return val if val else fallback
    except Exception:
        return fallback


class CursorPage(Gtk.Box):
    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._build_ui()

    def _build_ui(self) -> None:
        page = Adw.PreferencesPage()
        page.set_vexpand(True)
        page.add(self._build_theme_group())
        page.add(self._build_general_group())
        page.add(self._build_visibility_group())
        page.add(self._build_advanced_group())
        self.append(page)

    # ── helpers ──────────────────────────────────────────────────────────────

    def _switch_row(
        self, title: str, subtitle: str, setting_key: str, default: bool, hypr_key: str
    ) -> Adw.SwitchRow:
        row = Adw.SwitchRow()
        row.set_title(title)
        row.set_subtitle(subtitle)
        row.set_active(bool(_load(setting_key, default)))

        def on_change(r: Adw.SwitchRow, _param: object) -> None:
            val = "true" if r.get_active() else "false"
            _run(
                f"hyprctl keyword {hypr_key} {val} && {PERSIST} {hypr_key} {val} && hyprctl reload"
            )
            _save(setting_key, r.get_active())

        row.connect("notify::active", on_change)
        return row

    def _combo_row(
        self,
        title: str,
        subtitle: str,
        options: list[str],
        setting_key: str,
        default: str,
        hypr_key: str,
        values: list[str] | None = None,
    ) -> Adw.ComboRow:
        """Combo row where `values[i]` is the hyprctl value for `options[i]`."""
        vals = values if values is not None else options
        row = Adw.ComboRow()
        row.set_title(title)
        row.set_subtitle(subtitle)
        row.set_model(Gtk.StringList.new(options))
        saved = str(_load(setting_key, default))
        if saved in options:
            row.set_selected(options.index(saved))

        def on_change(r: Adw.ComboRow, _param: object) -> None:
            idx = r.get_selected()
            if idx >= len(options):
                return
            val = vals[idx]
            _run(
                f"hyprctl keyword {hypr_key} {val} && {PERSIST} {hypr_key} {val} && hyprctl reload"
            )
            _save(setting_key, options[idx])

        row.connect("notify::selected", on_change)
        return row

    def _spin_row(
        self,
        title: str,
        subtitle: str,
        setting_key: str,
        default: float,
        min_val: float,
        max_val: float,
        step: float,
        digits: int,
        hypr_key: str,
    ) -> Adw.ActionRow:
        row = Adw.ActionRow()
        row.set_title(title)
        row.set_subtitle(subtitle)
        saved = float(_load(setting_key, default))
        adj = Gtk.Adjustment(
            value=saved,
            lower=min_val,
            upper=max_val,
            step_increment=step,
            page_increment=step * 10,
        )
        spin = Gtk.SpinButton(adjustment=adj, digits=digits, valign=Gtk.Align.CENTER)
        spin.set_numeric(True)

        def on_change(s: Gtk.SpinButton) -> None:
            val = s.get_value()
            val_str = (
                str(int(val))
                if digits == 0
                else f"{val:.{digits}f}".rstrip("0").rstrip(".")
            )
            _run(
                f"hyprctl keyword {hypr_key} {val_str} && {PERSIST} {hypr_key} {val_str} && hyprctl reload"
            )
            _save(setting_key, val)

        spin.connect("value-changed", on_change)
        row.add_suffix(spin)
        row.set_activatable_widget(spin)
        return row

    # ── sections ─────────────────────────────────────────────────────────────

    def _build_theme_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Theme")

        # Theme dropdown — populated from installed cursor theme directories
        themes = _get_cursor_themes()
        current_theme = _gsettings_get("cursor-theme", "Adwaita")

        theme_row = Adw.ComboRow()
        theme_row.set_title("Cursor Theme")
        theme_row.set_subtitle("Installed cursor themes")
        theme_row.set_model(Gtk.StringList.new(themes))
        if current_theme in themes:
            theme_row.set_selected(themes.index(current_theme))
        self._themes = themes
        self._theme_row = theme_row

        # Size spin row
        try:
            current_size = int(_gsettings_get("cursor-size", "24"))
        except (ValueError, TypeError):
            current_size = 24
        size_adj = Gtk.Adjustment(
            value=current_size,
            lower=8,
            upper=128,
            step_increment=2,
            page_increment=8,
        )
        size_spin = Gtk.SpinButton(
            adjustment=size_adj, digits=0, valign=Gtk.Align.CENTER
        )
        size_spin.set_numeric(True)
        self._size_spin = size_spin

        size_row = Adw.ActionRow()
        size_row.set_title("Cursor Size")
        size_row.set_subtitle("Size in pixels")
        size_row.add_suffix(size_spin)
        size_row.set_activatable_widget(size_spin)

        def apply_theme_size(*_args: object) -> None:
            idx = self._theme_row.get_selected()
            theme = self._themes[idx] if idx < len(self._themes) else "Adwaita"
            size = int(self._size_spin.get_value())
            _run(
                f"hyprctl setcursor '{theme}' {size}"
                f" && gsettings set org.gnome.desktop.interface cursor-theme '{theme}'"
                f" && gsettings set org.gnome.desktop.interface cursor-size {size}"
                " && hyprctl reload"
            )

        theme_row.connect("notify::selected", apply_theme_size)
        size_spin.connect("value-changed", apply_theme_size)

        group.add(theme_row)
        group.add(size_row)
        return group

    def _build_general_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("General")

        group.add(
            self._combo_row(
                "Hardware Cursors",
                "Auto = disable on multi-GPU / Nvidia",
                ["Auto", "Enabled", "Disabled"],
                "cursor/no_hardware_cursors",
                "Auto",
                "cursor:no_hardware_cursors",
                values=["2", "0", "1"],
            )
        )
        group.add(
            self._switch_row(
                "Enable Hyprcursor",
                "Use Hyprcursor theme format",
                "cursor/enable_hyprcursor",
                True,
                "cursor:enable_hyprcursor",
            )
        )
        group.add(
            self._switch_row(
                "Disable Cursor Warps",
                "Don't warp cursor when focusing or using keybinds",
                "cursor/no_warps",
                False,
                "cursor:no_warps",
            )
        )
        group.add(
            self._switch_row(
                "Persistent Warps",
                "Remember cursor position per window when warping back",
                "cursor/persistent_warps",
                False,
                "cursor:persistent_warps",
            )
        )
        group.add(
            self._combo_row(
                "Warp on Workspace Change",
                "Move cursor to last focused window on workspace switch",
                ["Disabled", "Enabled", "Force"],
                "cursor/warp_on_change_workspace",
                "Disabled",
                "cursor:warp_on_change_workspace",
                values=["0", "1", "2"],
            )
        )
        group.add(
            self._spin_row(
                "Zoom Factor",
                "Cursor magnification (1.0 = no zoom)",
                "cursor/zoom_factor",
                1.0,
                1.0,
                10.0,
                0.1,
                1,
                "cursor:zoom_factor",
            )
        )
        group.add(
            self._switch_row(
                "Zoom Rigid",
                "Lock zoom to cursor position (don't follow screen edges)",
                "cursor/zoom_rigid",
                False,
                "cursor:zoom_rigid",
            )
        )
        return group

    def _build_visibility_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Visibility")

        group.add(
            self._spin_row(
                "Inactive Timeout",
                "Seconds before hiding cursor (0 = never)",
                "cursor/inactive_timeout",
                0,
                0,
                3600,
                1,
                0,
                "cursor:inactive_timeout",
            )
        )
        group.add(
            self._switch_row(
                "Hide on Key Press",
                "Hide cursor while typing until mouse is moved",
                "cursor/hide_on_key_press",
                False,
                "cursor:hide_on_key_press",
            )
        )
        group.add(
            self._switch_row(
                "Hide on Touch",
                "Hide cursor on touchscreen input until mouse is used",
                "cursor/hide_on_touch",
                True,
                "cursor:hide_on_touch",
            )
        )
        group.add(
            self._switch_row(
                "Hide on Tablet",
                "Hide cursor on tablet input until mouse is used",
                "cursor/hide_on_tablet",
                False,
                "cursor:hide_on_tablet",
            )
        )
        group.add(
            self._switch_row(
                "No Break FS VRR",
                "Don't disable fullscreen VRR when cursor moves",
                "cursor/no_break_fs_vrr",
                False,
                "cursor:no_break_fs_vrr",
            )
        )
        return group

    def _build_advanced_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Advanced")

        group.add(
            self._spin_row(
                "Hotspot Padding",
                "Padding around the cursor hotspot in pixels",
                "cursor/hotspot_padding",
                1,
                0,
                64,
                1,
                0,
                "cursor:hotspot_padding",
            )
        )
        return group
