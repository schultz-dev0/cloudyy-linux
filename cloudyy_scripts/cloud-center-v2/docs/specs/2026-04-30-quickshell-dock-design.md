# Quickshell Dock — Design Spec
**Date:** 2026-04-30  
**Status:** Approved

---

## Overview

A macOS-style animated dock for the cloudyy linux Hyprland setup, implemented as a Quickshell QML module. Features Gaussian spotlight magnification on hover (ported from hyprdock), autohide with a bottom-center activation zone, pinned apps + running apps with deduplication, and the cloudyy glass aesthetic (matugen colors, Papirus-Dark icons).

---

## Architecture

```
~/.config/quickshell/
├── shell.qml                      ← register QuickDock.Dock {}
└── modules/
    └── dock/
        ├── qmldir
        ├── Dock.qml               ← PanelWindow, pinned list, frame loop, autohide
        └── DockIcon.qml           ← single icon slot
```

`shell.qml` adds `import "modules/dock" as QuickDock` and `QuickDock.Dock {}` alongside Bar and Overview.

---

## Dock.qml — PanelWindow

**Positioning:**
- `anchors { bottom: true }` only — no left/right, so it floats centered
- `exclusiveZone: 0` — dock floats over windows, does not push them up
- `WlrLayershell.layer: WlrLayer.Top`
- `implicitWidth` computed from icon count: `iconCount * (iconSize + iconSpacing) + 2 * paddingH`
- `implicitHeight` covers dock body + bottom gap

**Pinned apps array (top of file, easy to edit):**
```qml
readonly property var pinnedApps: [
    { class: "firefox",          exec: "firefox",          icon: "firefox"   },
    { class: "dev.zed.Zed",      exec: "zeditor",          icon: "zed"       },
    { class: "kitty",            exec: "kitty",             icon: "kitty"     },
    { class: "thunar",           exec: "thunar",            icon: "thunar"    },
    { class: "spotify",          exec: "spotify",           icon: "spotify"   },
]
```

**App list merging:**
1. Start with `pinnedApps`
2. Append any window from `HyprlandData.windowList` whose class does not match any pinned entry
3. Result: pinned apps always appear first, running-only apps appended after
4. Each entry carries: `class`, `exec`, `icon`, `isRunning` (bool), `isPinned` (bool)

**IpcHandler** target `"dock"` — exposes `toggle()`, `show()`, `hide()`.

---

## Autohide

Two-layer approach within a single PanelWindow:

1. **Trigger zone** — a thin `MouseArea` (height ~4px) anchored to the bottom of the PanelWindow, centered, ~320px wide. Always active. `onEntered` → `dockVisible = true`.
2. **Dock body** — slides up/down via `YAnimation` on `dockVisible`. A `MouseArea` covering the full dock body sets `dockVisible = false` on `onExited`.
3. **Fullscreen override** — if any window on the active monitor has `fullscreen > 0`, force `dockVisible = false` regardless of hover state.

Slide animation: `NumberAnimation` on `y`, duration 200ms, `Easing.OutCubic` (show) / `Easing.InCubic` (hide).

---

## Gaussian Magnification (Spotlight)

Ported directly from hyprdock's spotlight math.

**Parameters (tunable at top of Dock.qml):**
```qml
readonly property int   iconSize:    48    // base icon size px
readonly property real  maxScale:    1.8   // peak magnification
readonly property real  spread:      2.2   // σ = iconSize × spread
readonly property int   frameMs:     16    // ~60fps
```

**Per-frame computation (Timer interval: frameMs):**
```
σ = iconSize × spread
for each icon i at center position x_i:
    d = |mouseX - x_i|
    targetScale[i] = 1 + (maxScale - 1) × exp(-0.5 × (d/σ)²)
```
Mouse position is tracked via a `MouseArea` covering the full dock body, `hoverEnabled: true`, `onPositionChanged` updates `mouseX`. When mouse is outside dock, all `targetScale[i] = 1.0`.

**Smooth animation in DockIcon.qml (exponential decay lerp):**
```
lerp = 1 - exp(-12 × dt)       // dt = frameMs / 1000
currentScale += (targetScale - currentScale) × lerp
```
`currentScale` drives the icon's `scale` property directly — no QML `Behavior` needed, the frame loop handles it.

---

## DockIcon.qml

Properties received from parent:
- `targetScale: real` — desired scale from Gaussian computation
- `appData: var` — `{ class, exec, icon, isRunning, isPinned }`
- `iconSize: int`
- `frameMs: int`

Internal:
- `property real currentScale: 1.0` — lerped each frame tick
- `property bool hovered: false`
- `property bool pressed: false`

**Icon image:** `file:///usr/share/icons/Papirus-Dark/48x48/apps/${appData.icon}.svg`  
Fallback chain on `Image.Error`: `Quickshell.iconPath(appData.icon, Quickshell.iconPath("application-x-executable", ""))`

**Running indicator:** 4px × 4px `Rectangle`, `radius: 2`, `color: Theme.primary`, centered below icon. `visible: appData.isRunning`.

**Glass overlay:** `Rectangle` anchored to icon area, `color: Qt.rgba(Theme.surface_container.r, g, b, hovered ? 0.25 : 0.0)`, `radius: iconSize * 0.22 * currentScale`, transitions on hover.

**Click logic:**
```qml
onClicked: {
    if (appData.isRunning)
        Hyprland.dispatch("focuswindow class:" + appData.class)
    else
        dock.launch(["uwsm-app", "--", appData.exec])
}
```
`dock.launch(cmd)` uses the same `Component { id: procProto; Process {} }` + `function launch(cmd)` pattern from Bar.qml, defined on the Dock.qml PanelWindow.

---

## Visual Design

- **Background pill:** `Qt.rgba(Theme.surface_container.r, g, b, 0.72)` with `border: 1px rgba(Theme.outline_variant, 0.18)`, `radius: iconSize * 0.55`
- **Glass shine:** subtle top-edge highlight `rgba(255,255,255, 0.06)`, 1px border inset
- **Icon size:** 48px base, scales up to `48 × maxScale` px at cursor center
- **Spacing:** 10px between icons; 14px horizontal padding on pill
- **Bottom gap:** 10px between dock pill bottom and screen edge (via `margins.bottom`)
- **Font:** JetBrainsMono Nerd Font (matches Bar.qml)

---

## Out of Scope

- Spotlight search (app/file/web) — separate project, to be specced after dock ships
- Drag-to-reorder pinned apps
- Context menus on icons
- Multi-monitor dock (single monitor for now)

---

## Success Criteria

1. Dock appears centered at bottom, floating, with correct width for app count
2. Mouse hovering bottom-center activation zone slides dock up
3. Mouse leaving dock slides it back down; fullscreen windows force-hide it
4. Icons magnify with Gaussian falloff around cursor, animate smoothly
5. Pinned apps always visible; running-only apps appended; running indicator dot shown
6. Clicking a running app focuses it; clicking a not-running app launches it
7. Papirus-Dark icons load; fallback to Qt icon theme on error
8. `quickshell ipc call dock toggle` works
