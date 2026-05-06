# Quickshell Spotlight — Design Spec
**Date:** 2026-05-01
**Status:** Approved

---

## Overview

A macOS-style spotlight search overlay for the cloudyy linux Hyprland setup, implemented as a Quickshell QML module. Features app search (from `.desktop` files), file search (`fd`, depth 2 from `$HOME`), and a persistent web search row (DuckDuckGo). Triggered by `Super+D` or a pinned dock button. No backdrop — floats over the desktop. Glass aesthetic matching the dock (matugen colors).

---

## Architecture

```
~/.config/quickshell/
├── shell.qml                          ← add QuickSpotlight.Spotlight {}
├── modules/dock/Dock.qml              ← add pinned search button (always left)
└── modules/spotlight/
    ├── qmldir
    ├── Spotlight.qml                  ← PanelWindow, input, results list, IPC
    ├── SpotlightRow.qml               ← single result row component
    └── search.sh                      ← app + file search, outputs JSON lines
```

`shell.qml` adds `import "modules/spotlight" as QuickSpotlight` and `QuickSpotlight.Spotlight {}` alongside Bar, Dock, and Overview.

---

## Spotlight.qml — PanelWindow

**Positioning:**
- `anchors { top: true; left: true; right: true }` — spans full width, anchored top
- `exclusiveZone: 0` — floats over windows
- `WlrLayershell.layer: WlrLayer.Top`
- `WlrLayershell.namespace: "quickshell:spotlight"`
- `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive` when visible, `OnDemand` when hidden
- `implicitHeight` sized to content (search bar + results)
- No backdrop — `color: "transparent"` on PanelWindow

**Tunables (top of file, easy to edit):**
```qml
readonly property string webSearchUrl:   "https://duckduckgo.com/?q="
readonly property int    overlayWidth:   640
readonly property int    topMargin:      80
readonly property int    maxFileResults: 10
readonly property int    debounceMs:     120
```

**State:**
```qml
property bool   spotlightVisible: false
property string query:            ""
property var    results:          []
property int    selectedIndex:    0
```

**Search debounce:** A `Timer` with `interval: debounceMs` restarts on every `query` change and fires `runSearch()` when it triggers. This prevents a `Process` spawn on every keystroke.

**Search process:** A single `Process` instance runs `search.sh <query>`. On `stdout` data, results are parsed from newline-delimited JSON and written to `results`. On new search start, `results` is cleared immediately so stale data never shows.

**Keyboard handling:** `Keys.onPressed` on the root item:
- `Escape` → `spotlightVisible = false`
- `Up` → `selectedIndex = Math.max(0, selectedIndex - 1)`
- `Down` → `selectedIndex = Math.min(results.length - 1, selectedIndex + 1)` (web row is index `results.length`)
- `Return` → activate item at `selectedIndex`

**Results list:** `ListView` bound to `results`. Always appended with one web search row at the bottom when `query` is non-empty. `selectedIndex` drives visual highlight.

**Running app detection:** After `search.sh` results are parsed, QML cross-references each app result's `exec` field against `HyprlandData.windowList` by class name. If a match is found, `isRunning: true` is set and activation dispatches `focuswindow class:` instead of launching.

**Slide animation:** `NumberAnimation` on `y`, duration 180ms, `Easing.OutCubic` (show) / `Easing.InCubic` (hide).

**Click outside to close:** `MouseArea` covering the full PanelWindow with `acceptedButtons: Qt.LeftButton`, `propagateComposedEvents: true`, `onClicked: spotlightVisible = false`. The content panel sits on top and absorbs its own clicks.

---

## SpotlightRow.qml

Properties:
- `resultData: var` — `{ type, name, icon, exec, path }` or `{ type: "web", query }`
- `isSelected: bool`

Layout: horizontal row, 40px tall. 28px icon (Papirus-Dark for apps, `folder`/`text-x-generic` for files, globe for web). Name label + subtitle (exec for apps, path for files, "Search DDG for …" for web). Glass highlight rectangle when `isSelected`.

---

## search.sh

Called as `search.sh <query>`. Outputs newline-delimited JSON to stdout.

**App search** (always runs):
```bash
grep -ril "name=<query>" /usr/share/applications/ \
  | xargs grep -l "^Exec=" \
  | while read f; do
      name=$(grep -m1 "^Name=" "$f" | cut -d= -f2-)
      icon=$(grep -m1 "^Icon=" "$f" | cut -d= -f2-)
      exec=$(grep -m1 "^Exec=" "$f" | sed 's/ %.//g' | cut -d= -f2-)
      printf '{"type":"app","name":"%s","icon":"%s","exec":"%s"}\n' "$name" "$icon" "$exec"
    done
```

**File search** (runs when query length ≥ 4):
```bash
fd "$query" "$HOME" --max-depth 2 --max-results "$MAX_FILE_RESULTS" \
  | while read path; do
      name=$(basename "$path")
      printf '{"type":"file","name":"%s","path":"%s"}\n' "$name" "$path"
    done
```

Web row is not emitted by the script — it is always appended in QML when query is non-empty.

---

## Dock Integration

`Dock.qml` gains a search button pinned to the left, always in that position regardless of running apps.

- A separate `Item` (not part of the `mergedApps` Repeater) placed to the left of `iconsRow`
- Same size as dock icons (48px), same glass hover overlay as `DockIcon`
- Icon: `system-search` (Papirus-Dark) with fallback to `edit-find`
- `onClicked: Hyprland.dispatch("global quickshell:spotlight:toggle")`

The `dockWidth` calculation gains `+ iconSize + iconSpacing` to account for the fixed search button.

---

## IPC + Keybind

**IpcHandler** target `"spotlight"` — exposes `toggle()`, `show()`, `hide()`.

**Hyprland keybind** (to be added to `~/.config/hypr/source/keybinds.conf`):
```conf
bind = SUPER, D, global, quickshell:spotlight:toggle
```

---

## Visual Design

- **Panel background:** `Qt.rgba(Theme.surface_container.r, g, b, 0.92)`, `radius: 14`, `border: 1px rgba(Theme.outline_variant, 0.25)`
- **Search bar:** 48px tall, `font-size: 16px`, JetBrainsMono Nerd Font, separated from results by a 1px divider
- **Section labels:** 10px uppercase, `Theme.outline_variant` color
- **Selected row:** `Qt.rgba(Theme.primary.r, g, b, 0.22)` background fill
- **Web row:** always last, slightly dimmer text, globe icon

---

## Out of Scope

- Drag-to-reorder results
- Calculator / unit conversion
- Recent items / search history
- Multi-monitor support

---

## Success Criteria

1. `Super+D` opens overlay at top-center, 640px wide, 80px from top
2. Dock search button (always left) toggles overlay
3. Typing searches apps immediately, files at 4+ chars
4. Arrow keys navigate, Enter activates, Escape closes
5. Web row always present at bottom when query non-empty; opens DDG in browser
6. App launches via `uwsm-app --`; files via `xdg-open`; running apps focused via `Hyprland.dispatch`
7. `quickshell ipc call spotlight toggle` works
8. `webSearchUrl` tunable at top of file changes search engine
