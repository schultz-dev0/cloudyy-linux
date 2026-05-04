# Cursor Page + Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a full Cursor settings page (`lib/cursor_page.py`) covering all Hyprland `cursor {}` options plus theme/size, then reorganize the sidebar into Visuals / Input & Display / System categories with "System Overview" pinned at the bottom.

**Architecture:** The Cursor page is a new `Gtk.Box` subclass (`CursorPage`) registered as the lazy page `__cursor__`, consistent with `bluetooth_page.py`, `monitor_editor.py`, etc. The sidebar change is purely structural: two `Gtk.ListBox` widgets (scrollable categories + pinned bottom item) instead of one, plus updated category groupings. `hypr_persist.sh` is extended to persist cursor settings to `user_cursor.conf`.

**Tech Stack:** Python 3, GTK 4, Libadwaita 1, Hyprland (`hyprctl`), `gsettings`, bash

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `hypr_persist.sh` | Modify | Add cursor keys to LAYOUT, PAGE_KEYS; add `user_cursor.conf` write target |
| `lib/cursor_page.py` | Create | `CursorPage` class — all cursor settings UI |
| `cloud-center.py` | Modify | Register `__cursor__`; update categories; restructure `_build_sidebar()` for pinned item |

---

## Task 1: Extend `hypr_persist.sh` with cursor support

**Files:**
- Modify: `hypr_persist.sh`

### Step 1.1 — Add `CURSOR_CONF` bash variable

After line 56 (`INPUT_CONF=...`), add:

```bash
CURSOR_CONF="${HYPR_DIR}/user-configs/user_cursor.conf"
```

Full context of the lines to change (lines 52–59 before edit):
```bash
HYPR_DIR="${HOME}/.config/hypr"
USER_CONF="${HYPR_DIR}/user-configs/user_lookandfeel.conf"
ANIM_CONF="${HYPR_DIR}/user-configs/user_animations.conf"
INPUT_CONF="${HYPR_DIR}/user-configs/user_input.conf"
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$MODE" "$ARG1" "$ARG2" "$STATE_FILE" "$USER_CONF" "$ANIM_CONF" "$INPUT_CONF" "$HYPRLAND_CONF" <<'PYEOF'
```

After edit:
```bash
HYPR_DIR="${HOME}/.config/hypr"
USER_CONF="${HYPR_DIR}/user-configs/user_lookandfeel.conf"
ANIM_CONF="${HYPR_DIR}/user-configs/user_animations.conf"
INPUT_CONF="${HYPR_DIR}/user-configs/user_input.conf"
CURSOR_CONF="${HYPR_DIR}/user-configs/user_cursor.conf"
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$MODE" "$ARG1" "$ARG2" "$STATE_FILE" "$USER_CONF" "$ANIM_CONF" "$INPUT_CONF" "$CURSOR_CONF" "$HYPRLAND_CONF" <<'PYEOF'
```

Note: `$CURSOR_CONF` is inserted as `sys.argv[8]` and `$HYPRLAND_CONF` shifts to `sys.argv[9]`.

- [ ] Make this edit

### Step 1.2 — Update Python `sys.argv` assignments

Inside the `<<'PYEOF'` block, lines 63–72 currently read:
```python
mode           = sys.argv[1]
arg1           = sys.argv[2]
arg2           = sys.argv[3]
state_path     = sys.argv[4]
conf_path      = sys.argv[5]
anim_conf_path = sys.argv[6]
input_conf_path = sys.argv[7]
hyprland_path  = sys.argv[8]
```

Replace with:
```python
mode             = sys.argv[1]
arg1             = sys.argv[2]
arg2             = sys.argv[3]
state_path       = sys.argv[4]
conf_path        = sys.argv[5]
anim_conf_path   = sys.argv[6]
input_conf_path  = sys.argv[7]
cursor_conf_path = sys.argv[8]
hyprland_path    = sys.argv[9]
```

- [ ] Make this edit

### Step 1.3 — Add cursor entries to `LAYOUT` dict

At the end of the `LAYOUT` dict (after the last `"input:touchpad:scroll_factor"` entry, before the closing `}`), add:

```python
    "cursor:no_hardware_cursors":      ("cursor", None, "no_hardware_cursors"),
    "cursor:enable_hyprcursor":        ("cursor", None, "enable_hyprcursor"),
    "cursor:no_warps":                 ("cursor", None, "no_warps"),
    "cursor:persistent_warps":         ("cursor", None, "persistent_warps"),
    "cursor:warp_on_change_workspace": ("cursor", None, "warp_on_change_workspace"),
    "cursor:zoom_factor":              ("cursor", None, "zoom_factor"),
    "cursor:zoom_rigid":               ("cursor", None, "zoom_rigid"),
    "cursor:inactive_timeout":         ("cursor", None, "inactive_timeout"),
    "cursor:hide_on_key_press":        ("cursor", None, "hide_on_key_press"),
    "cursor:hide_on_touch":            ("cursor", None, "hide_on_touch"),
    "cursor:hide_on_tablet":           ("cursor", None, "hide_on_tablet"),
    "cursor:no_break_fs_vrr":          ("cursor", None, "no_break_fs_vrr"),
    "cursor:hotspot_padding":          ("cursor", None, "hotspot_padding"),
    "cursor:theme":                    ("cursor", None, "theme"),
    "cursor:size":                     ("cursor", None, "size"),
```

- [ ] Make this edit

### Step 1.4 — Add `cursor` to `PAGE_KEYS`

In the `PAGE_KEYS` dict (after the `"input"` entry), add:

```python
    "cursor": {
        "cursor:no_hardware_cursors",
        "cursor:enable_hyprcursor",
        "cursor:no_warps",
        "cursor:persistent_warps",
        "cursor:warp_on_change_workspace",
        "cursor:zoom_factor",
        "cursor:zoom_rigid",
        "cursor:inactive_timeout",
        "cursor:hide_on_key_press",
        "cursor:hide_on_touch",
        "cursor:hide_on_tablet",
        "cursor:no_break_fs_vrr",
        "cursor:hotspot_padding",
        "cursor:theme",
        "cursor:size",
    },
```

- [ ] Make this edit

### Step 1.5 — Load cursor conf state on startup

Find the state loading loop (around line 200):
```python
for cfg in (Path(conf_path), Path(anim_conf_path), Path(input_conf_path)):
    state.update(parse_state_from_conf(cfg))
```

Replace with:
```python
for cfg in (Path(conf_path), Path(anim_conf_path), Path(input_conf_path), Path(cursor_conf_path)):
    state.update(parse_state_from_conf(cfg))
```

- [ ] Make this edit

### Step 1.6 — Build and write `user_cursor.conf`

Find the three `build_lines` + `write_conf` calls (around lines 289–308):
```python
main_lines = build_lines(
    "# Cloud Center — user-configs/user_cloud-center.conf",
    ["general", "decoration"],
)
anim_lines = build_lines(
    "# Cloud Center — user-configs/user_animations.conf",
    ["animations"],
)
input_lines = build_lines(
    "# Cloud Center — user-configs/user_input.conf",
    ["input"],
)

write_conf(conf_path, main_lines)
write_conf(anim_conf_path, anim_lines)
write_conf(input_conf_path, input_lines)

print(f"[hypr_persist] wrote {conf_path}")
print(f"[hypr_persist] wrote {anim_conf_path}")
print(f"[hypr_persist] wrote {input_conf_path}")
```

Replace with:
```python
main_lines = build_lines(
    "# Cloud Center — user-configs/user_cloud-center.conf",
    ["general", "decoration"],
)
anim_lines = build_lines(
    "# Cloud Center — user-configs/user_animations.conf",
    ["animations"],
)
input_lines = build_lines(
    "# Cloud Center — user-configs/user_input.conf",
    ["input"],
)
cursor_lines = build_lines(
    "# Cloud Center — user-configs/user_cursor.conf",
    ["cursor"],
)

write_conf(conf_path, main_lines)
write_conf(anim_conf_path, anim_lines)
write_conf(input_conf_path, input_lines)
write_conf(cursor_conf_path, cursor_lines)

print(f"[hypr_persist] wrote {conf_path}")
print(f"[hypr_persist] wrote {anim_conf_path}")
print(f"[hypr_persist] wrote {input_conf_path}")
print(f"[hypr_persist] wrote {cursor_conf_path}")
```

- [ ] Make this edit

### Step 1.7 — Add cursor conf to `source_specs`

Find `source_specs` (around line 314):
```python
source_specs = [
    ("~/.config/hypr/user-configs/user_cloud-center.conf", conf_path, "Cloud Center managed overrides"),
    ("~/.config/hypr/user-configs/user_animations.conf", anim_conf_path, "Cloud Center animation overrides"),
    ("~/.config/hypr/user-configs/user_input.conf", input_conf_path, "Cloud Center input overrides"),
]
```

Replace with:
```python
source_specs = [
    ("~/.config/hypr/user-configs/user_cloud-center.conf", conf_path, "Cloud Center managed overrides"),
    ("~/.config/hypr/user-configs/user_animations.conf", anim_conf_path, "Cloud Center animation overrides"),
    ("~/.config/hypr/user-configs/user_input.conf", input_conf_path, "Cloud Center input overrides"),
    ("~/.config/hypr/user-configs/user_cursor.conf", cursor_conf_path, "Cloud Center cursor overrides"),
]
```

- [ ] Make this edit

### Step 1.8 — Verify

```bash
cd ~/cloudyy_scripts/cloud-center-v2
bash hypr_persist.sh cursor:inactive_timeout 5
```

Expected output includes:
```
[hypr_persist] persisted cursor:inactive_timeout = 5
[hypr_persist] wrote /home/<user>/.config/hypr/user-configs/user_cursor.conf
```

Verify the conf file was created:
```bash
cat ~/.config/hypr/user-configs/user_cursor.conf
```

Expected: contains `cursor { inactive_timeout = 5 }` block.

Reset:
```bash
bash hypr_persist.sh cursor:inactive_timeout 0
```

- [ ] Run verification

### Step 1.9 — Commit

```bash
git add hypr_persist.sh
git commit -m "feat: extend hypr_persist.sh with cursor {} settings support"
```

- [ ] Commit

---

## Task 2: Create `lib/cursor_page.py`

**Files:**
- Create: `lib/cursor_page.py`

### Step 2.1 — Create the file

Create `lib/cursor_page.py` with the following content:

```python
"""Cloud Center — Cursor settings page."""
from __future__ import annotations

import subprocess
import threading
from pathlib import Path

from gi.repository import Adw, GLib, Gtk

import lib.utility as utility

PERSIST = str(Path(__file__).resolve().parents[1] / "hypr_persist.sh")


def _run(cmd: str) -> None:
    utility.execute_command(cmd)


def _save(key: str, value: object) -> None:
    threading.Thread(target=utility.save_setting, args=(key, value), daemon=True).start()


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
            capture_output=True, text=True, timeout=3,
        )
        return r.stdout.strip().strip("'\"")
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

    def _switch_row(self, title: str, subtitle: str, setting_key: str,
                    default: bool, hypr_key: str) -> Adw.SwitchRow:
        row = Adw.SwitchRow()
        row.set_title(title)
        row.set_subtitle(subtitle)
        row.set_active(bool(_load(setting_key, default)))

        def on_change(r: Adw.SwitchRow, _param: object) -> None:
            val = "true" if r.get_active() else "false"
            _run(f"hyprctl keyword {hypr_key} {val} && {PERSIST} {hypr_key} {val}")
            _save(setting_key, r.get_active())

        row.connect("notify::active", on_change)
        return row

    def _combo_row(self, title: str, subtitle: str, options: list[str],
                   setting_key: str, default: str, hypr_key: str,
                   values: list[str] | None = None) -> Adw.ComboRow:
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
            _run(f"hyprctl keyword {hypr_key} {val} && {PERSIST} {hypr_key} {val}")
            _save(setting_key, options[idx])

        row.connect("notify::selected", on_change)
        return row

    def _spin_row(self, title: str, subtitle: str, setting_key: str,
                  default: float, min_val: float, max_val: float,
                  step: float, digits: int, hypr_key: str) -> Adw.ActionRow:
        row = Adw.ActionRow()
        row.set_title(title)
        row.set_subtitle(subtitle)
        saved = float(_load(setting_key, default))
        adj = Gtk.Adjustment(
            value=saved, lower=min_val, upper=max_val,
            step_increment=step, page_increment=step * 10,
        )
        spin = Gtk.SpinButton(adjustment=adj, digits=digits, valign=Gtk.Align.CENTER)
        spin.set_numeric(True)

        def on_change(s: Gtk.SpinButton) -> None:
            val = s.get_value()
            val_str = str(int(val)) if digits == 0 else f"{val:.{digits}f}".rstrip("0").rstrip(".")
            _run(f"hyprctl keyword {hypr_key} {val_str} && {PERSIST} {hypr_key} {val_str}")
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
        current_size = int(_gsettings_get("cursor-size", "24") or 24)
        size_adj = Gtk.Adjustment(
            value=current_size, lower=8, upper=128,
            step_increment=2, page_increment=8,
        )
        size_spin = Gtk.SpinButton(adjustment=size_adj, digits=0, valign=Gtk.Align.CENTER)
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
                f" && hyprctl keyword cursor:theme '{theme}'"
                f" && hyprctl keyword cursor:size {size}"
                f" && gsettings set org.gnome.desktop.interface cursor-theme '{theme}'"
                f" && gsettings set org.gnome.desktop.interface cursor-size {size}"
                f" && {PERSIST} cursor:theme '{theme}'"
                f" && {PERSIST} cursor:size {size}"
            )

        theme_row.connect("notify::selected", apply_theme_size)
        size_spin.connect("value-changed", apply_theme_size)

        group.add(theme_row)
        group.add(size_row)
        return group

    def _build_general_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("General")

        group.add(self._combo_row(
            "Hardware Cursors",
            "Auto = disable on multi-GPU / Nvidia",
            ["Auto", "Enabled", "Disabled"],
            "cursor/no_hardware_cursors", "Auto",
            "cursor:no_hardware_cursors",
            values=["2", "0", "1"],
        ))
        group.add(self._switch_row(
            "Enable Hyprcursor", "Use Hyprcursor theme format",
            "cursor/enable_hyprcursor", True, "cursor:enable_hyprcursor",
        ))
        group.add(self._switch_row(
            "Disable Cursor Warps", "Don't warp cursor when focusing or using keybinds",
            "cursor/no_warps", False, "cursor:no_warps",
        ))
        group.add(self._switch_row(
            "Persistent Warps", "Remember cursor position per window when warping back",
            "cursor/persistent_warps", False, "cursor:persistent_warps",
        ))
        group.add(self._combo_row(
            "Warp on Workspace Change",
            "Move cursor to last focused window on workspace switch",
            ["Disabled", "Enabled", "Force"],
            "cursor/warp_on_change_workspace", "Disabled",
            "cursor:warp_on_change_workspace",
            values=["0", "1", "2"],
        ))
        group.add(self._spin_row(
            "Zoom Factor", "Cursor magnification (1.0 = no zoom)",
            "cursor/zoom_factor", 1.0, 1.0, 10.0, 0.1, 1,
            "cursor:zoom_factor",
        ))
        group.add(self._switch_row(
            "Zoom Rigid", "Lock zoom to cursor position (don't follow screen edges)",
            "cursor/zoom_rigid", False, "cursor:zoom_rigid",
        ))
        return group

    def _build_visibility_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Visibility")

        group.add(self._spin_row(
            "Inactive Timeout", "Seconds before hiding cursor (0 = never)",
            "cursor/inactive_timeout", 0, 0, 3600, 1, 0,
            "cursor:inactive_timeout",
        ))
        group.add(self._switch_row(
            "Hide on Key Press", "Hide cursor while typing until mouse is moved",
            "cursor/hide_on_key_press", False, "cursor:hide_on_key_press",
        ))
        group.add(self._switch_row(
            "Hide on Touch", "Hide cursor on touchscreen input until mouse is used",
            "cursor/hide_on_touch", True, "cursor:hide_on_touch",
        ))
        group.add(self._switch_row(
            "Hide on Tablet", "Hide cursor on tablet input until mouse is used",
            "cursor/hide_on_tablet", False, "cursor:hide_on_tablet",
        ))
        group.add(self._switch_row(
            "No Break FS VRR", "Don't disable fullscreen VRR when cursor moves",
            "cursor/no_break_fs_vrr", False, "cursor:no_break_fs_vrr",
        ))
        return group

    def _build_advanced_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Advanced")

        group.add(self._spin_row(
            "Hotspot Padding", "Padding around the cursor hotspot in pixels",
            "cursor/hotspot_padding", 1, 0, 64, 1, 0,
            "cursor:hotspot_padding",
        ))
        return group
```

- [ ] Create `lib/cursor_page.py` with the above content

### Step 2.2 — Syntax check

```bash
cd ~/cloudyy_scripts/cloud-center-v2
python3 -c "import lib.cursor_page; print('OK')"
```

Expected: `OK`

- [ ] Run syntax check

### Step 2.3 — Commit

```bash
git add lib/cursor_page.py
git commit -m "feat: add CursorPage with theme, general, visibility, and advanced sections"
```

- [ ] Commit

---

## Task 3: Register cursor page and reorganize sidebar in `cloud-center.py`

**Files:**
- Modify: `cloud-center.py:54-97` (imports, CLI aliases)
- Modify: `cloud-center.py:296-321` (builtins, categories, `_build_sidebar`)
- Modify: `cloud-center.py:427-434` (`_lazy_builders`)
- Modify: `cloud-center.py:536-552` (`navigate_to_page`)

### Step 3.1 — Add import

After the existing `import lib.rgb_page as rgb_page` line (line 63), add:

```python
import lib.cursor_page as cursor_page
```

- [ ] Add import

### Step 3.2 — Add CLI alias

In `CLI_PAGE_ALIASES` dict (lines 82–97), add:

```python
    "cursor": "__cursor__",
```

- [ ] Add CLI alias

### Step 3.3 — Add cursor to `builtins` dict

In `_build_sidebar()`, find the `builtins` dict (lines 296–303):

```python
        builtins = {
            "__mon__": {"id": "__mon__", "title": "Monitors", "icon": "video-display-symbolic"},
            "__bt__": {"id": "__bt__", "title": "Bluetooth", "icon": "bluetooth-active-symbolic"},
            "__wifi__": {"id": "__wifi__", "title": "Wi-Fi", "icon": "network-wireless-signal-good-symbolic"},
            "__audio__": {"id": "__audio__", "title": "Audio", "icon": "audio-speakers-symbolic"},
            "__rgb__": {"id": "__rgb__", "title": "RGB Lighting", "icon": "applications-games-symbolic"},
            "__hkbm__": {"id": "__hkbm__", "title": "Keybind Manager", "icon": "input-keyboard-symbolic"},
        }
```

Replace with:

```python
        builtins = {
            "__cursor__": {"id": "__cursor__", "title": "Cursor", "icon": "input-mouse-symbolic"},
            "__mon__": {"id": "__mon__", "title": "Monitors", "icon": "video-display-symbolic"},
            "__bt__": {"id": "__bt__", "title": "Bluetooth", "icon": "bluetooth-active-symbolic"},
            "__wifi__": {"id": "__wifi__", "title": "Wi-Fi", "icon": "network-wireless-signal-good-symbolic"},
            "__audio__": {"id": "__audio__", "title": "Audio", "icon": "audio-speakers-symbolic"},
            "__rgb__": {"id": "__rgb__", "title": "RGB Lighting", "icon": "applications-games-symbolic"},
            "__hkbm__": {"id": "__hkbm__", "title": "Keybind Manager", "icon": "input-keyboard-symbolic"},
        }
```

- [ ] Make this edit

### Step 3.4 — Replace `categories` and restructure `_build_sidebar()`

The current sidebar builds everything into a single `_nav_list` inside a `ScrolledWindow`. We need to add a second pinned `ListBox` at the bottom for "System Overview" (the `home` page).

Find the section in `_build_sidebar()` from `categories = ...` through `box.append(scroll)` (lines 304–319):

```python
        categories: list[tuple[str, list[str]]] = [
            ("Home", ["home"]),
            ("Visuals", ["appearance", ACTIVE_SHELL_TAB, "hyprland"]),
            ("System", ["input", "__mon__", "__bt__", "__wifi__", "__audio__", "__rgb__"]),
            ("Tools", ["__hkbm__"]),
        ]

        for title, ids in categories:
            self._nav_list.append(self._make_nav_category_row(title))
            for page_id in ids:
                page = yaml_pages.get(page_id) or builtins.get(page_id)
                if page:
                    self._nav_list.append(self._make_nav_row(page))

        scroll.set_child(self._nav_list)
        box.append(scroll)

        return box
```

Replace with:

```python
        categories: list[tuple[str, list[str]]] = [
            ("Visuals",         ["appearance", ACTIVE_SHELL_TAB, "hyprland"]),
            ("Input & Display", ["input", "__cursor__", "__mon__", "__hkbm__"]),
            ("System",          ["__bt__", "__wifi__", "__audio__", "__rgb__"]),
        ]

        for title, ids in categories:
            self._nav_list.append(self._make_nav_category_row(title))
            for page_id in ids:
                page = yaml_pages.get(page_id) or builtins.get(page_id)
                if page:
                    self._nav_list.append(self._make_nav_row(page))

        scroll.set_child(self._nav_list)
        box.append(scroll)

        # Pinned bottom: System Overview (home page)
        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        self._pinned_list = Gtk.ListBox()
        self._pinned_list.add_css_class("sidebar-surface")
        self._pinned_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._pinned_list.add_css_class("sidebar-nav-list")
        self._pinned_list.connect("row-selected", self._on_nav_row_selected)

        home_page = yaml_pages.get("home")
        if home_page:
            home_display = dict(home_page)
            home_display["title"] = "System Overview"
            home_row = self._make_nav_row(home_display)
            # Re-register under "home" key so navigate_to_page("home") still works
            self._nav_rows["home"] = home_row
            self._pinned_list.append(home_row)

        box.append(self._pinned_list)

        return box
```

- [ ] Make this edit

### Step 3.5 — Add `_pinned_list` attribute initialisation

In `__init__` or wherever `_nav_list` is declared as `None` initially, check if `_pinned_list` also needs to be initialised. Search for `self._nav_list` initialisation:

```bash
grep -n "_nav_list" ~/cloudyy_scripts/cloud-center-v2/cloud-center.py | head -20
```

If there is a line like `self._nav_list: Gtk.ListBox | None = None`, add alongside it:
```python
self._pinned_list: Gtk.ListBox | None = None
```

- [ ] Check and add if needed

### Step 3.6 — Update `_on_nav_row_selected` to deselect the other list

Find `_on_nav_row_selected` (lines 554–560):

```python
    def _on_nav_row_selected(self, listbox: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        """Handle row selection in the sidebar nav list."""
        if row is None:
            return
        page_id = getattr(row, "_page_id", None)
        if page_id:
            self._on_nav_selected(row, page_id)
```

Replace with:

```python
    def _on_nav_row_selected(self, listbox: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        """Handle row selection in the sidebar nav list."""
        if row is None:
            return
        # Deselect the other list so only one item is ever highlighted
        if listbox is self._nav_list and self._pinned_list is not None:
            self._pinned_list.unselect_all()
        elif listbox is self._pinned_list and self._nav_list is not None:
            self._nav_list.unselect_all()
        page_id = getattr(row, "_page_id", None)
        if page_id:
            self._on_nav_selected(row, page_id)
```

- [ ] Make this edit

### Step 3.7 — Update `navigate_to_page` to handle pinned list

Find `navigate_to_page` (lines 536–552). The current code uses `self._nav_list.select_row(row)` which won't work for the home row which now lives in `_pinned_list`. Replace the selection block:

Current:
```python
        row = self._nav_rows.get(page_id)
        if row and self._nav_list is not None:
            self._nav_list.select_row(row)
        return True
```

Replace with:
```python
        row = self._nav_rows.get(page_id)
        if row:
            parent = row.get_parent()
            if isinstance(parent, Gtk.ListBox):
                parent.select_row(row)
                if parent is self._nav_list and self._pinned_list is not None:
                    self._pinned_list.unselect_all()
                elif parent is self._pinned_list and self._nav_list is not None:
                    self._nav_list.unselect_all()
        return True
```

- [ ] Make this edit

### Step 3.8 — Add cursor to `_lazy_builders`

Find `_lazy_builders` dict (lines 427–434):

```python
        self._lazy_builders = {
            "__bt__":    lambda: bluetooth_page.BluetoothPage(self._toast_ov),
            "__wifi__":  lambda: wifi_page.WiFiPage(self._toast_ov),
            "__mon__":   lambda: monitor_editor.MonitorEditorPage(self._toast_ov),
            "__hkbm__":  lambda: keybind_manager.KeybindManagerPage(self._toast_ov),
            "__audio__": lambda: audio_page.AudioPage(self._toast_ov),
            "__rgb__":   lambda: rgb_page.RGBPage(self._toast_ov),
        }
```

Replace with:

```python
        self._lazy_builders = {
            "__cursor__": lambda: cursor_page.CursorPage(self._toast_ov),
            "__bt__":    lambda: bluetooth_page.BluetoothPage(self._toast_ov),
            "__wifi__":  lambda: wifi_page.WiFiPage(self._toast_ov),
            "__mon__":   lambda: monitor_editor.MonitorEditorPage(self._toast_ov),
            "__hkbm__":  lambda: keybind_manager.KeybindManagerPage(self._toast_ov),
            "__audio__": lambda: audio_page.AudioPage(self._toast_ov),
            "__rgb__":   lambda: rgb_page.RGBPage(self._toast_ov),
        }
```

- [ ] Make this edit

### Step 3.9 — Syntax check

```bash
cd ~/cloudyy_scripts/cloud-center-v2
python3 -c "
import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
import cloud_center
print('OK')
" 2>&1 | head -20
```

If `cloud_center` import fails due to module name, try:
```bash
python3 -c "
import ast, sys
with open('cloud-center.py') as f:
    src = f.read()
ast.parse(src)
print('AST OK')
"
```

Expected: `AST OK`

- [ ] Run syntax check

### Step 3.10 — Launch and smoke test

```bash
cd ~/cloudyy_scripts/cloud-center-v2
python3 cloud-center.py
```

Verify:
1. Sidebar shows **Visuals**, **Input & Display**, **System** categories — no "Home" or "Tools"
2. "System Overview" is pinned at the bottom below a separator
3. **Input & Display** contains: Input, Cursor, Monitors, Keybind Manager
4. Clicking **Cursor** loads the page with Theme, General, Visibility, Advanced groups
5. Theme dropdown is populated with installed cursor themes
6. Toggling "Hide on Key Press" shows no errors in terminal
7. Clicking "System Overview" navigates to the home page and highlights correctly; clicking anything in the main list deselects System Overview

- [ ] Launch and smoke test

### Step 3.11 — Commit

```bash
git add cloud-center.py
git commit -m "feat: register cursor page, reorganize sidebar with pinned System Overview"
```

- [ ] Commit
