# Overview Hover Peek — Design Spec

**Date:** 2026-06-26  
**Status:** Pending user review  
**Scope:** Quickshell workspace overview module (`~/.config/quickshell/overview/`)

## Problem

The overview is a strong workspace switcher (Super+Tab, mini thumbnails in a glass panel), but users cannot inspect or focus individual windows without switching to that workspace first. macOS Mission Control solves this with a full exposé mode, but adding a separate feature would split the mental model and duplicate entry points.

The user chose **hover peek**: mouse users get a larger floating preview above a workspace tile with clickable windows, while the existing keyboard flow stays unchanged.

## Goals

1. Hover a workspace tile (~150ms) → enlarged peek popup appears above the tile (or below if no vertical room).
2. Click a window thumbnail inside the peek → focus that window and close overview.
3. Click tile chrome / label → switch workspace (unchanged).
4. Super+Tab, arrow keys, and Super release behavior unchanged — **no peek on keyboard selection**.
5. Reuse existing `WorkspacePreview`, `WindowThumbnail`, and `ScreencopyView` pipeline.
6. Respect `Perf.animationsEnabled`; one live capture set for the hovered workspace only.

## Non-goals (v1)

- Keyboard-triggered peek (e.g. on Tab selection)
- Drag-and-drop windows between workspaces from peek
- Middle-click / right-click to close windows from peek
- Peek on touch devices (no hover)
- Replacing the centered panel layout or adding a second overview shortcut
- Wallpaper inside peek

## Design decisions (brainstorming)

| Decision | Choice |
|----------|--------|
| Architecture | **Shared popup** at `OverviewWidget` level (not per-tile popups) |
| Peek trigger | Mouse hover with 150ms show delay |
| Peek dismiss | 200ms hide delay after leaving tile + peek; immediate on overview close |
| Peek placement | Above tile, horizontally centered; flip below if insufficient space; clamp to overlay bounds |
| Peek size | ~2.2× tile preview area; max dimensions capped to screen margins |
| Keyboard UX | Unchanged — peek is mouse-only |
| Lightweight overview | Hovered workspace gets live capture while peek is open (exception to tile-only rule) |
| Tile click | Label / non-preview chrome → switch workspace; peek windows → focus window |

## Interaction model

| Action | Result |
|--------|--------|
| Hover tile ≥150ms | Show peek for that workspace |
| Move into peek | Peek stays open (hover bridge between tile and popup) |
| Leave tile and peek | Hide peek after 200ms |
| Click window in peek | `requestFocusWindow` → close overview → focus window |
| Click tile (outside peek) | `requestWorkspace` → switch workspace (unchanged) |
| Super+Tab / ←/→ | Cycle workspace selection — no peek |
| Super release | Activate selected workspace (unchanged) |
| Esc / backdrop click | Close overview (unchanged) |
| Overview closes | Dismiss peek immediately |
| Flickable scroll | Hide peek while scrolling |

## Architecture

```
OverviewWidget
  ├── panel (existing glass shell + workspace tiles)
  └── WorkspacePeekPopup (new, z above panel)
        ├── positioned via mapToItem(hoveredTile)
        └── WorkspacePreview (interactive: true)
              └── WindowThumbnail × N (clickable)
```

### Why shared popup at widget level

- **Single capture pipeline** — only one hovered workspace pays screencopy cost at a time.
- **No panel clipping** — peek renders outside the panel `Rectangle`/`Flickable`.
- **Clean tile-to-tile handoff** — one popup repositions and swaps content instead of competing per-tile overlays.

### Data flow

1. `WorkspaceTile` emits `peekRequested()` on hover enter (after delay) and `peekDismissed()` on hover leave.
2. `OverviewWidget` tracks `peekWorkspaceId`, `peekAnchorItem`, positions `WorkspacePeekPopup`.
3. Peek receives `windows`, `monitorData`, `toplevelByAddress` from widget (same helpers as tiles).
4. `WorkspacePreview` with `interactive: true` forwards window clicks via `requestFocusWindow`.
5. Existing `Overview.qml` `focusWindow()` path handles focus + overview close.

## Components

### `WorkspacePeekPopup.qml` (new)

- Inputs: `visible`, `anchorItem`, `workspaceId`, `windows`, `monitorData`, `toplevelByAddress`, `overviewActive`
- Computes global position from `anchorItem.mapToItem(root, 0, 0)` with above/below flip and horizontal clamp
- Glass card shell matching tile styling (radius 16, shadow, bottom label strip)
- `opacity` / `scale` enter animation when `Perf.animationsEnabled`
- `MouseArea` on shell accepts hover to keep peek alive (does not steal tile click when peek hidden)
- Output signal: `requestFocusWindow(windowData)`

Suggested sizing:

```javascript
readonly property real peekScale: 2.2
readonly property int peekWidth: Math.min(anchorItem.width * peekScale, overlayWidth - margin * 2)
readonly property int peekHeight: Math.min(
    (anchorItem.height - labelStripHeight) * peekScale + labelStripHeight,
    availableHeightAboveOrBelow
)
```

### `OverviewWidget.qml` (edit)

- Properties: `peekWorkspaceId` (-1 when hidden), `peekAnchorItem`
- Timers: `peekShowTimer` (150ms), `peekHideTimer` (200ms)
- On tile `peekRequested(workspaceId, tileItem)`: cancel hide timer, set anchor, show peek
- On tile `peekDismissed()`: start hide timer unless mouse is over peek
- On `Flickable` movement / `overviewActive` false: force hide peek
- Wire peek `requestFocusWindow` → existing `requestFocusWindow` signal
- Pass `tileCaptureActive` override: peek workspace always captures when visible

### `WorkspaceTile.qml` (edit)

- Replace single full-tile `MouseArea` with hover-aware handling:
  - `hoverEnabled: true`
  - `onEntered` → start show timer → emit `peekRequested`
  - `onExited` → emit `peekDismissed`
  - `onClicked` → `requestWorkspace` (only when peek is not the click target — tile body clicks still switch WS)
- Signals: `peekRequested(int workspaceId)`, `peekDismissed()`
- Property `peekActive` from parent to suppress duplicate show while already peeking this tile

### `WorkspacePreview.qml` (edit)

- New property: `interactive` (default `false`)
- New signal: `requestFocusWindow(var windowData)`
- Pass `interactive` to `WindowThumbnail` delegates

### `WindowThumbnail.qml` (edit)

- New property: `interactive` (default `false`)
- When `interactive`: add `MouseArea` with `cursorShape: PointingHandCursor`, `onClicked` → bubble focus request
- Hover highlight: subtle border tint when interactive + hovered

### `qmldir`

- Register `WorkspacePeekPopup 1.0 WorkspacePeekPopup.qml`

## Styling

- Peek card: same tokens as `WorkspaceTile` (`Theme.glassSection`, primary border when workspace is active)
- Label strip: `WORKSPACE N` — same as tile
- Window hover in peek: primary-tinted border (2px)
- Enter animation: opacity 0→1, scale 0.92→1.0, 140ms `OutCubic` when animations enabled
- Exit: 100ms fade (no scale on exit to avoid layout jitter)

## Performance safeguards

1. Peek `Loader` inactive when `peekWorkspaceId < 0`
2. `captureSource: null` when peek hidden
3. Max 8 windows per peek (existing `windowsToShow` cap)
4. Only hovered workspace captures — not all tiles
5. Hide peek during Flickable scroll to avoid reposition thrash

## Error handling

- Empty workspace: peek shows "empty" state; tile click still switches workspace
- Missing toplevel: fallback icon rect (existing behavior)
- Anchor item destroyed / tile scrolled off: dismiss peek
- Multi-monitor: peek only on focused monitor overlay (existing `Overview` pattern)

## Testing

```bash
quickshell ipc call overview toggle
# hover tiles, click windows in peek
journalctl --user -u quickshell -n 50 --no-pager
```

Manual:

- [ ] Hover tile → peek appears above after brief delay
- [ ] Move mouse into peek → stays open
- [ ] Leave tile + peek → peek dismisses
- [ ] Click window in peek → focuses window, overview closes
- [ ] Click tile → switches workspace (unchanged)
- [ ] Super+Tab cycle → no peek appears
- [ ] Peek near top edge → flips below tile
- [ ] Peek near screen edge → clamps horizontally
- [ ] Scroll workspace row → peek hides
- [ ] Lightweight overview ON → peek still shows live capture for hovered WS
- [ ] Closing overview → peek gone, no GPU spike

## File summary

| File | Action |
|------|--------|
| `overview/modules/overview/WorkspacePeekPopup.qml` | Create |
| `overview/modules/overview/OverviewWidget.qml` | Edit — peek lifecycle + positioning |
| `overview/modules/overview/WorkspaceTile.qml` | Edit — hover signals |
| `overview/modules/overview/WorkspacePreview.qml` | Edit — interactive mode |
| `overview/modules/overview/WindowThumbnail.qml` | Edit — click handler |
| `overview/modules/overview/qmldir` | Edit — register peek |

## Future (out of scope)

- Clickable windows in tile mini-previews (without hover)
- Keyboard peek on selected workspace
- Middle-click close from peek
