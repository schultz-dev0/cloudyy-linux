# Cursor Page + Sidebar Redesign

**Date:** 2026-04-29  
**Status:** Approved — ready for implementation

---

## Overview

Two related changes:

1. **New Cursor settings page** (`lib/cursor_page.py`) covering all Hyprland `cursor {}` settings plus cursor theme and size.
2. **Sidebar reorganization** — new "Input & Display" section, "System Overview" pinned at the bottom.

---

## 1. Cursor Page

### Registration

- Page ID: `__cursor__`
- Added to `builtins` dict in `cloud-center.py` alongside other lazy pages:
  ```python
  "__cursor__": {"id": "__cursor__", "title": "Cursor", "icon": "input-mouse-symbolic"},
  ```
- Lazy-loaded on first navigation:
  ```python
  "__cursor__": lambda: cursor_page.CursorPage(self._toast_overlay),
  ```
- Import: `from lib import cursor_page` at top of `cloud-center.py`

### File

`lib/cursor_page.py` — class `CursorPage(Gtk.Box)`, following the same pattern as `keybind_manager.py` and `monitor_editor.py`. Uses `Adw.PreferencesPage` + `Adw.PreferencesGroup` sections identical to what the YAML builder produces.

### Sections

#### Theme
| Widget | Setting | Apply mechanism |
|--------|---------|-----------------|
| Dropdown (ComboRow) | Cursor theme name | `hyprctl setcursor <theme> <size>` + `gsettings set org.gnome.desktop.interface cursor-theme` + write `env = XCURSOR_THEME,<theme>` via `hypr_persist.sh` |
| Spinner | Cursor size (px) | Same as above but size field. Common values: 16, 20, 24, 32, 48, 64 |

Theme dropdown is populated dynamically by scanning:
- `/usr/share/icons/`
- `~/.local/share/icons/`
- `~/.icons/`

A directory qualifies as a cursor theme if it contains a `cursors/` subdirectory.

#### General
| Widget | Setting | Hyprland key |
|--------|---------|--------------|
| Dropdown (Auto/On/Off) | Hardware Cursors | `cursor:no_hardware_cursors` → 2/0/1 |
| Toggle | Enable Hyprcursor | `cursor:enable_hyprcursor` |
| Toggle | Disable Cursor Warps | `cursor:no_warps` |
| Toggle | Persistent Warps | `cursor:persistent_warps` |
| Dropdown (Disabled/Enabled/Force) | Warp on Workspace Change | `cursor:warp_on_change_workspace` → 0/1/2 |
| Spinner (min 1.0, step 0.1) | Zoom Factor | `cursor:zoom_factor` |
| Toggle | Zoom Rigid | `cursor:zoom_rigid` |

#### Visibility
| Widget | Setting | Hyprland key |
|--------|---------|--------------|
| Spinner (min 0, step 1) | Inactive Timeout (seconds, 0 = never) | `cursor:inactive_timeout` |
| Toggle | Hide on Key Press | `cursor:hide_on_key_press` |
| Toggle | Hide on Touch | `cursor:hide_on_touch` |
| Toggle | Hide on Tablet | `cursor:hide_on_tablet` |
| Toggle | No Break FS VRR | `cursor:no_break_fs_vrr` |

#### Advanced
| Widget | Setting | Hyprland key |
|--------|---------|--------------|
| Spinner (min 0, step 1) | Hotspot Padding (px) | `cursor:hotspot_padding` |

### Persistence

`hypr_persist.sh` has a hardcoded LAYOUT dict and writes to three specific conf files. It must be extended to support cursor keys.

**Changes to `hypr_persist.sh`:**

1. Add all cursor keys to the `LAYOUT` dict:
   ```python
   "cursor:no_hardware_cursors":     ("cursor", None, "no_hardware_cursors"),
   "cursor:enable_hyprcursor":       ("cursor", None, "enable_hyprcursor"),
   "cursor:no_warps":                ("cursor", None, "no_warps"),
   "cursor:persistent_warps":        ("cursor", None, "persistent_warps"),
   "cursor:warp_on_change_workspace":("cursor", None, "warp_on_change_workspace"),
   "cursor:zoom_factor":             ("cursor", None, "zoom_factor"),
   "cursor:zoom_rigid":              ("cursor", None, "zoom_rigid"),
   "cursor:inactive_timeout":        ("cursor", None, "inactive_timeout"),
   "cursor:hide_on_key_press":       ("cursor", None, "hide_on_key_press"),
   "cursor:hide_on_touch":           ("cursor", None, "hide_on_touch"),
   "cursor:hide_on_tablet":          ("cursor", None, "hide_on_tablet"),
   "cursor:no_break_fs_vrr":         ("cursor", None, "no_break_fs_vrr"),
   "cursor:hotspot_padding":         ("cursor", None, "hotspot_padding"),
   "cursor:theme":                   ("cursor", None, "theme"),
   "cursor:size":                    ("cursor", None, "size"),
   ```

2. Add `cursor` to `PAGE_KEYS`.

3. Add `CURSOR_CONF` variable pointing to `user_cursor.conf` and add a `write_conf(cursor_conf_path, build_lines(..., ["cursor"]))` call alongside the existing three.

**Apply pattern for cursor settings:**
```
hyprctl keyword cursor:<key> <value> && ~/cloudyy_scripts/cloud-center-v2/hypr_persist.sh cursor:<key> <value>
```

**Theme/size apply:**
- Live: `hyprctl setcursor <theme> <size>` (immediate cursor swap without reload) + `hyprctl keyword cursor:theme <theme>` + `hyprctl keyword cursor:size <size>`
- Persist: `hypr_persist.sh cursor:theme <theme>` + `hypr_persist.sh cursor:size <size>` → writes `user_cursor.conf`
- GTK compat: also call `gsettings set org.gnome.desktop.interface cursor-theme <theme>` and `gsettings set org.gnome.desktop.interface cursor-size <size>` so GTK apps pick up the change

### State persistence

Current theme/size are read back on page init via `gsettings get org.gnome.desktop.interface cursor-theme/cursor-size` to pre-select the correct values.

---

## 2. Sidebar Reorganization

### Changes to `cloud-center.py`

#### `builtins` dict — add cursor entry
```python
"__cursor__": {"id": "__cursor__", "title": "Cursor", "icon": "input-mouse-symbolic"},
```

#### `categories` list — replace existing
```python
categories: list[tuple[str, list[str]]] = [
    ("Visuals",         ["appearance", ACTIVE_SHELL_TAB, "hyprland"]),
    ("Input & Display", ["input", "__cursor__", "__mon__", "__hkbm__"]),
    ("System",          ["__bt__", "__wifi__", "__audio__", "__rgb__"]),
]
```

The `home` page is **not** in this list — it moves to the pinned bottom area.

#### `_build_sidebar()` structural change

The sidebar box currently contains: header → search → scroll(nav_list).

New structure: header → search → scroll(nav_list) → separator → pinned_list

```
Gtk.Box (vertical)
├── Adw.HeaderBar
├── Gtk.SearchEntry
├── Gtk.ScrolledWindow [vexpand=True]
│   └── Gtk.ListBox (_nav_list)  ← categorized pages, no home
├── Gtk.Separator
└── Gtk.ListBox (_pinned_list)   ← System Overview only
```

The `home` page is renamed to **"System Overview"** in the pinned list row title (the YAML `title` field can stay as-is; the pinned row overrides the display title).

Both `_nav_list` and `_pinned_list` connect to `_on_nav_row_selected`. When either list selects a row, the other is programmatically deselected via `list.unselect_all()`.

The `_nav_rows` dict includes the home row (keyed `"home"`) so that `navigate_to_page("home")` still works.

---

## Files Changed

| File | Change |
|------|--------|
| `lib/cursor_page.py` | **New file** — `CursorPage` class |
| `cloud-center.py` | Add cursor to builtins + lazy loader; update categories; restructure `_build_sidebar()` for pinned item |
| `hypr_persist.sh` | Add cursor keys to LAYOUT dict, PAGE_KEYS, and a new `user_cursor.conf` write target |

No changes to `config.yaml` or `lib/rows.py`.
