# Rules & Startup Page — Design Spec

**Date:** 2026-05-07
**Status:** Approved

---

## Overview

Add a "Rules & Startup" page to Cloud Center — a single tabbed page with four sections:
Window Rules, Layer Rules, Autostart, and Environment Variables. Each section is a
list editor with add/edit/delete dialogs. Changes apply live to the running compositor
(write conf + `hyprctl reload`). The Apply button commits the current state as the new
confirmed baseline; Discard reverts to the last confirmed baseline.

---

## Sidebar Integration

- Registered as `__rules_startup` in `cloud-center.py` under the **Hyprland** category
- Same pattern as `__keybinds` (Keybind Manager)
- On first Apply: `hcm.ensure_user_config_sourced()` injects a `source =` line into
  `~/.config/hypr/hyprland.conf` pointing at the managed conf file

---

## Module Structure

Single file: `lib/rules_startup_page.py`

```
RulesStartupPage(Gtk.Box)
├── _WindowRulesTab
├── _LayerRulesTab
├── _AutostartTab
└── _EnvVarsTab
```

The parent page owns:
- `Adw.ViewStack` with the four tabs
- `Adw.ViewSwitcher` tab bar across the top
- Shared footer: conf file path label (left) + Discard + Apply buttons (right)
- Dirty banner (shown when any tab has unsaved changes)
- `_apply_live()` — called by any tab after any mutation; serializes all four sections,
  writes the conf file, runs `hyprctl reload`

Each tab is initialized with a reference to its parent `RulesStartupPage` (`self._page`)
so it can call `self._page._apply_live()` after mutations.

Each tab owns:
- `_items: list[DataClass]` — current in-memory state
- `_baseline: list[DataClass]` — last confirmed state (copy set on Apply or initial load)
- `_build_ui()` → scrollable list box + "Add" button in header
- `_refresh_list()` → rebuild list rows from `_items`
- `_on_add()` / `_on_edit(idx)` / `_on_delete(idx)` → open dialog, mutate `_items`,
  call `self._page._apply_live()`
- `is_dirty() -> bool` — `_items != _baseline`
- `serialize() -> list[str]` — returns conf lines for this section (no markers)
- `parse(lines: list[str]) -> None` — populate `_items` from raw conf lines

---

## Data Models

Effects dicts use the effect name as key and a string arg as value. Toggle-only effects
(float, center, opaque, etc.) always have value `"on"`. Numeric effects store the arg
string as-is (e.g. `"0.9"`, `"1080 1080"`).

```python
@dataclass
class WindowRule:
    name: str                        # optional label, written as `name = …`
    matchers: list[tuple[str, str]]  # e.g. [("match:class", "^(zen)$")]
    effects: dict[str, str]          # e.g. {"float": "on", "size": "1080 1080"}

@dataclass
class LayerRule:
    name: str
    namespace: str                   # value for `match:namespace`
    effects: dict[str, str]          # e.g. {"blur": "on", "ignore_alpha": "0.2"}

@dataclass
class AutostartEntry:
    command: str
    exec_once: bool                  # True → exec-once, False → exec

@dataclass
class EnvVar:
    name: str
    value: str
```

---

## Conf File

**Path:** `~/.config/hypr/user-configs/user_rules_startup.conf`

Four marker-delimited sections in a fixed order:

```
# --- CC: Window Rules ---
windowrule {
    name        = zen-browser
    match:class = ^(zen)$
    float       = on
    size        = 1080 1080
    opaque      = on
}
# --- CC: End Window Rules ---

# --- CC: Layer Rules ---
layerrule {
    name            = quickshell_panel
    match:namespace = ^(quickshell)$
    blur            = on
    ignore_alpha    = 0.2
}
# --- CC: End Layer Rules ---

# --- CC: Autostart ---
exec-once = waybar
exec       = hyprpaper
# --- CC: End Autostart ---

# --- CC: Environment ---
env = XCURSOR_THEME,Bibata-Modern-Ice
env = XCURSOR_SIZE,24
# --- CC: End Environment ---
```

Parser reads between marker pairs to populate each tab's `_items`. Writer serializes
all four sections in order and overwrites the file atomically (write to `.tmp`, then
`Path.replace()`).

---

## Apply Logic

| Action | What happens |
|---|---|
| Add / Edit / Delete (any tab) | Mutate `_items`, call `_apply_live()`: write conf → `hyprctl reload` → show dirty banner |
| Apply button | Set `_baseline = copy(_items)` for all tabs → `_apply_live()` → clear dirty banner → ensure source line injected |
| Discard button | Set `_items = copy(_baseline)` for all tabs → `_apply_live()` → clear dirty banner |

**Env vars and autostart** do not live-apply meaningfully (Hyprland reads env at startup,
autostart runs at startup). They still go through `_apply_live()` so the file stays
consistent, but a toast reminds the user: "Log out / restart Hyprland to apply env/autostart changes."

---

## Dialogs

### Window Rule Dialog (`Adw.Dialog` subclass)

Fields:
- **Name** — single text entry (optional)
- **Matchers** — dynamic list of rows, each with:
  - Dropdown: `match:class`, `match:title`, `match:tag`, `match:xwayland`, `match:floating`, `match:fullscreen`
  - Text entry for the value (regex)
  - "Pick" button → `WindowPickerDialog` lists running windows via `hyprctl clients -j`, fills class on select
  - "+" link to add another matcher row
- **Effects** — toggle rows for common effects, each showing its arg field when toggled on:
  - `float` — toggle only
  - `size` — two integer fields (width × height)
  - `opacity` — decimal entry (0.0–1.0)
  - `opaque` — toggle only
  - `center` — toggle only
  - `pin` — toggle only
  - `noblur` — toggle only
  - `immediate` — toggle only
- **Live preview** — monospace block showing exact `windowrule { … }` output, updates on every field change
- Validated: at least one matcher required. Add/Save button disabled until valid.

### Layer Rule Dialog (`Adw.Dialog` subclass)

Fields:
- **Name** — text entry (optional)
- **Namespace** — single text entry for `match:namespace` regex value
- **Effects** — toggle rows:
  - `blur` — toggle only
  - `ignore_alpha` — decimal entry
  - `animation` — text entry (e.g. `slide down`)
  - `dim_around` — toggle only
  - `xray` — toggle only
  - `no_anim` — toggle only
- **Live preview** — monospace `layerrule { … }` block

### Autostart Dialog (`Adw.Dialog` subclass)

Fields:
- **Command** — text entry
- **Re-run on every reload** — toggle (off = `exec-once`, on = `exec`)
- "Pick app" button → `AppPickerDialog` reads `.desktop` files from `/usr/share/applications`
  and `~/.local/share/applications`, shows a searchable list, fills command on select

### Env Var Dialog (`Adw.Dialog` subclass)

Fields:
- **Name** — text entry, validated as `[A-Za-z_][A-Za-z0-9_]*`
- **Value** — text entry (free text, preserves commas after first)
- **Live preview** — `env = NAME,value`

---

## Window Picker

`_WindowPickerDialog` (simple `Adw.Dialog`):
- Runs `hyprctl clients -j` in a thread on open
- Shows a scrollable list of running windows (class + title)
- Selecting one closes the dialog and fills the matcher value field in the parent dialog

---

## List Row Layout

Each row in a tab's list box:

```
┌─────────────────────────────────────────────────────┐
│ [Rule name / command]                   [Edit][Del] │
│ matcher subtitle (dim)                              │
│ [effect pill] [effect pill] ...                     │
└─────────────────────────────────────────────────────┘
```

- Window Rules: name (bold) / matchers as subtitle / effect pills
- Layer Rules: name / namespace as subtitle / effect pills
- Autostart: command / `exec-once` or `exec` badge
- Env Vars: `NAME` (bold) / `value` as subtitle

---

## Error Handling

- `hyprctl reload` failure: toast "Hyprland reload failed — check your config"
- Conf file write failure: toast with error message; in-memory state unchanged
- `hyprctl clients -j` failure in window picker: show empty list with "Could not list windows"
- Invalid env var name: inline error label below field, Save button disabled

---

## Files Changed

| File | Change |
|---|---|
| `lib/rules_startup_page.py` | New file — full implementation |
| `cloud-center.py` | Register `__rules_startup` page in sidebar |
