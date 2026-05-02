# Control Center Redesign

**Date:** 2026-05-02
**Branch:** dev
**Scope:** Hybrid — redesign tile grid + add media player card; keep existing sliders and notification list.

---

## Goal

Redesign `NotifPanel.qml` to look and feel like the macOS Control Center: labeled tiles with live status text, a macOS-style mixed-width tile grid, a now-playing media card, and a modular architecture so new tiles can be added with minimal effort.

---

## Panel Layout (top to bottom)

1. **Header row** — "Control Center" title (left) + current date/time (right)
2. **Tile grid** — macOS mixed layout (see below)
3. **Night Light popover** — floating, appears on right-click of the Night Light tile
4. **Display section** — brightness slider (existing, unchanged)
5. **Sound section** — volume slider (existing, unchanged)
6. **Media card** — new; playerctl/MPRIS now-playing widget
7. **Notification list** — existing, unchanged

---

## Tile Grid

Layout: 2-column grid. First tile (WiFi) spans both columns (full width). All other tiles are half-width.

| Tile | Width | Data source | Left-click | Right-click |
|---|---|---|---|---|
| WifiTile | full | `nmcli -t -f active,ssid dev wifi \| awk -F: '/^yes/{print $2}'` | open `nm-connection-editor` | — |
| DndTile | half | bound to `panel.dnd` prop | emit `panel.dndToggle()` | — |
| BluetoothTile | half | `bluetoothctl show \| awk '/Powered:/{print $2}'` → `yes`/`no` | open `cloud-center bluetooth` | — |
| DarkModeTile | half | `grep THEME_MODE ~/.config/hypr/theme_state/state.conf \| cut -d= -f2 \| tr -d '"'` → `dark`/`light` | run `theme_controller.sh toggle` | — |
| NightLightTile | half | `~/.cache/wltemp` + `pgrep -x hyprsunset` | toggle via `sliderController.toggleNightLight()` | show temp popover |

Each tile refreshes itself on `Component.onCompleted`. `WifiTile`, `BluetoothTile`, and `DarkModeTile` also expose a `refresh()` function that `NotifPanel` calls via `onOpenChanged: if (open) { ... }`. `DndTile` and `NightLightTile` are purely binding-based — no polling needed.

---

## Tile Architecture (Approach A — declarative children)

### `BaseTile.qml`

Base component for all half-width tiles:

```
properties:
  string  icon          — Nerd Font glyph
  string  label         — display name
  string  statusText    — live status ("On", "Off", "Connected", …)
  bool    active        — drives the teal highlight when true

signals:
  clicked()
  rightClicked()
```

Renders: icon (top-left) → label → statusText. Active state: teal background + border tint.

### Tile files

Each tile in `modules/controlcenter/tiles/` is a `BaseTile` with a `Process` (or binding) wired up. Each handles its own data fetch and state internally. `NightLightTile` additionally owns a `Popup` (Qt Quick Controls) for the temperature slider.

### `TileGrid.qml`

```
default property alias tiles: container.data
```

Internal layout: `GridLayout` with 2 columns. `WifiTile` sets `Layout.columnSpan: 2` on itself so it spans the full width. All other tiles use the default `columnSpan: 1`. The grid does not enforce tile type — callers are responsible for tile ordering. (`Grid` cannot be used here because it does not support `Layout.columnSpan`.)

### Adding a new tile

1. Create `modules/controlcenter/tiles/MyTile.qml` (extend `BaseTile`, wire up a `Process`)
2. Add `<MyTile />` inside `<TileGrid>` in `NotifPanel.qml`

---

## Night Light Tile — Popover Detail

- **Left-click** → toggle hyprsunset (reuse existing `sliderController.toggleNightLight()`)
- **Right-click** → open a `Popup` anchored to the tile's bottom-right corner
- Popup contains:
  - Label: "Night Light" + current temp value (e.g. "3500K")
  - Horizontal gradient slider (1000K warm → 6500K cool), warm-orange to cool-blue gradient on the track
  - Closes on click-outside (`closePolicy: Popup.CloseOnPressOutside`)
- Popup reads/writes `sliderController.nightLightTemp` and calls `sliderController.setNightLightTemp()`
- The existing standalone Night Light section in `NotifPanel.qml` is **removed** (replaced by this tile + popover)

---

## Media Card (`MediaCard.qml`)

Polls `playerctl` via `Process` on a 2 s `Timer`. Shows:

- **Album art**: `Image { source: artUrl }` where `artUrl` comes from `playerctl metadata mpris:artUrl`. Falls back to a gradient rectangle with a ♪ glyph if empty or load fails.
- **Track title** (truncated, ellipsis)
- **Artist name**
- **Player name** (small, muted — e.g. "Spotify")
- **Progress bar**: passive visual only (no scrubbing); width = `position / length`, updated on each poll
- **Controls**: prev (`playerctl previous`), play/pause (`playerctl play-pause`), next (`playerctl next`)

Hidden entirely when `playerctl status` returns no active player.

Data commands — fetched in two `Process` calls per poll cycle:

```bash
# 1. Status (determines whether to show the card at all)
playerctl status 2>/dev/null
# → "Playing", "Paused", "Stopped", or empty/error (no player)

# 2. Metadata (only run if status is not empty)
playerctl metadata --format '{{title}}\t{{artist}}\t{{mpris:artUrl}}\t{{mpris:length}}\t{{position}}' 2>/dev/null
# → tab-separated: title, artist, artUrl (file:// or https://), length (µs), position (s float)
```

`MediaCard.qml` runs the status check first; if the output is empty the card sets `visible: false` and skips the metadata fetch.

---

## `NotifPanel.qml` Changes

- **Remove**: inline `Toggle` component definition, `SliderIconButton` component, standalone Night Light `Rectangle` section, `InlineSlider` component definition (superseded by `Sliders.qml`'s `PillSlider`)
- **Add**: `TileGrid { WifiTile {} DndTile {} BluetoothTile {} DarkModeTile {} NightLightTile {} }`
- **Add**: `MediaCard { sliderController: panel.sliderController }` between Sound section and notification list
- **Keep**: Display section, Sound section, notification list (no changes)
- **Header**: add `Text` on the right showing current date/time via a `Timer` + `Qt.formatDateTime`

---

## File Checklist

| File | Status |
|---|---|
| `modules/controlcenter/tiles/BaseTile.qml` | new |
| `modules/controlcenter/tiles/WifiTile.qml` | new |
| `modules/controlcenter/tiles/DndTile.qml` | new |
| `modules/controlcenter/tiles/BluetoothTile.qml` | new |
| `modules/controlcenter/tiles/DarkModeTile.qml` | new |
| `modules/controlcenter/tiles/NightLightTile.qml` | new |
| `modules/controlcenter/TileGrid.qml` | new |
| `modules/controlcenter/MediaCard.qml` | new |
| `NotifPanel.qml` | modified |

No changes to `Sliders.qml`, `shell.qml`, `Bar.qml`, `Theme.qml`, or any overview/dock/spotlight modules.

---

## Out of Scope

- Bluetooth tile does not show paired device names (just On/Off)
- No scrubbing on the media progress bar
- No network speed display on the WiFi tile
- No battery widget (not in macOS screenshot scope; add later as a new tile)
- No changes to notification card design
