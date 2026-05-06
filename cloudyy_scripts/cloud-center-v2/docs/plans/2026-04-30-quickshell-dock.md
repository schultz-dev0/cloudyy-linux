# Quickshell Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS-style animated dock for Hyprland/Quickshell with Gaussian spotlight magnification, autohide, and cloudyy glass aesthetics.

**Architecture:** Two-file module (`Dock.qml` + `DockIcon.qml`) under `~/.config/quickshell/modules/dock/`. Dock.qml is the PanelWindow that owns the pinned app list, merges running apps from HyprlandData, drives a per-icon Gaussian magnification each frame, and manages autohide. DockIcon.qml owns one icon slot with its own lerp timer and click logic.

**Tech Stack:** Quickshell QML, Quickshell.Hyprland, WlrLayershell, HyprlandData service (existing), Theme.qml (existing matugen tokens), Papirus-Dark icon theme.

---

## File Map

| Status | Path | Purpose |
|--------|------|---------|
| **Create** | `~/.config/quickshell/modules/dock/qmldir` | QML module registration |
| **Create** | `~/.config/quickshell/modules/dock/Dock.qml` | PanelWindow: layout, app list, autohide, frame loop |
| **Create** | `~/.config/quickshell/modules/dock/DockIcon.qml` | Single icon: scale lerp, image, indicator, click |
| **Modify** | `~/.config/quickshell/shell.qml` | Register `QuickDock.Dock {}` |
| **Modify** | `~/.config/hypr/source/windowrules.conf` | Add blur layerrule for `quickshell:dock` |

---

## Task 1: Module scaffold + shell.qml wiring

**Files:**
- Create: `~/.config/quickshell/modules/dock/qmldir`
- Create: `~/.config/quickshell/modules/dock/Dock.qml` (stub)
- Create: `~/.config/quickshell/modules/dock/DockIcon.qml` (stub)
- Modify: `~/.config/quickshell/shell.qml`

- [ ] **Step 1: Create the modules/dock directory and qmldir**

```bash
mkdir -p ~/.config/quickshell/modules/dock
```

`~/.config/quickshell/modules/dock/qmldir`:
```
module QuickDock
Dock 1.0 Dock.qml
DockIcon 1.0 DockIcon.qml
```

- [ ] **Step 2: Create stub Dock.qml**

`~/.config/quickshell/modules/dock/Dock.qml`:
```qml
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dock
    anchors { bottom: true }
    implicitWidth: 300
    implicitHeight: 80
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

    Rectangle {
        anchors.centerIn: parent
        width: 200; height: 60
        radius: 14
        color: "#aa1e1e2e"
        Text {
            anchors.centerIn: parent
            text: "dock stub"
            color: "white"
            font.pixelSize: 12
        }
    }
}
```

- [ ] **Step 3: Create stub DockIcon.qml**

`~/.config/quickshell/modules/dock/DockIcon.qml`:
```qml
import QtQuick

Item {
    id: root
    width: 48
    height: 48

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: "#661e1e2e"
    }
}
```

- [ ] **Step 4: Register in shell.qml**

In `~/.config/quickshell/shell.qml`, add after the existing overview import:
```qml
import "modules/dock" as QuickDock
```
And inside `ShellRoot { ... }`, add after `QuickOverview.Overview {}`:
```qml
QuickDock.Dock {}
```

- [ ] **Step 5: Reload Quickshell and verify**

```bash
pkill -HUP quickshell 2>/dev/null || (pkill quickshell; sleep 0.3; quickshell &)
```

Expected: Quickshell reloads without error. A dark pill labeled "dock stub" is visible at the bottom center of the screen.

- [ ] **Step 6: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/qmldir modules/dock/Dock.qml modules/dock/DockIcon.qml shell.qml
git commit -m "feat: scaffold dock module, wire into shell.qml"
```

---

## Task 2: DockIcon — icon display, running indicator, hover

**Files:**
- Modify: `~/.config/quickshell/modules/dock/DockIcon.qml`

- [ ] **Step 1: Replace DockIcon.qml with full implementation**

`~/.config/quickshell/modules/dock/DockIcon.qml`:
```qml
import QtQuick
import Quickshell
import "../.."

Item {
    id: root

    required property var   appData        // { class, exec, icon, isRunning, isPinned }
    required property int   iconSize
    required property real  maxScale
    required property real  spread
    required property int   frameMs
    required property real  dockMouseX     // mouse X in iconsRow coordinates, -9999 = outside
    required property real  iconCenterX    // center X of this icon in iconsRow coordinates

    signal clicked()

    property bool hovered: false
    property bool pressed: false

    // ── Gaussian magnification ─────────────────────────────────────────────
    readonly property real targetScale: {
        if (dockMouseX < -100) return 1.0
        const d = Math.abs(dockMouseX - iconCenterX)
        const sigma = iconSize * spread
        return 1.0 + (maxScale - 1.0) * Math.exp(-0.5 * (d / sigma) * (d / sigma))
    }
    property real currentScale: 1.0

    Timer {
        interval: root.frameMs
        running: true
        repeat: true
        onTriggered: {
            const lerp = 1.0 - Math.exp(-12.0 * root.frameMs / 1000.0)
            root.currentScale += (root.targetScale - root.currentScale) * lerp
        }
    }

    width:  root.iconSize
    height: root.iconSize * root.maxScale + 6  // +6 for running dot below

    // ── Icon image ─────────────────────────────────────────────────────────
    Image {
        id: iconImg
        width:  root.iconSize
        height: root.iconSize
        anchors {
            bottom: parent.bottom
            bottomMargin: 6  // space for running dot
            horizontalCenter: parent.horizontalCenter
        }
        source: `file:///usr/share/icons/Papirus-Dark/48x48/apps/${root.appData.icon}.svg`
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        smooth: true
        scale: root.currentScale
        transformOrigin: Item.Bottom

        onStatusChanged: {
            if (status === Image.Error && source.toString().startsWith("file://"))
                source = Quickshell.iconPath(root.appData.icon,
                             Quickshell.iconPath("application-x-executable", ""))
        }

        // Glass hover overlay
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: root.iconSize * 0.22
            color: Qt.rgba(
                Theme.surface_container_high.r,
                Theme.surface_container_high.g,
                Theme.surface_container_high.b,
                root.pressed ? 0.4 : root.hovered ? 0.22 : 0.0
            )
            Behavior on color { ColorAnimation { duration: 100 } }
        }
    }

    // ── Running indicator dot ──────────────────────────────────────────────
    Rectangle {
        visible: root.appData.isRunning ?? false
        width: 4; height: 4
        radius: 2
        color: Theme.primary
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Mouse interaction ──────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered:  root.hovered = true
        onExited:   { root.hovered = false; root.pressed = false }
        onPressed:  root.pressed = true
        onReleased: root.pressed = false
        onClicked:  root.clicked()
    }
}
```

- [ ] **Step 2: Reload and verify DockIcon renders**

Reload Quickshell. The stub dock should still show (DockIcon isn't instantiated yet). No errors in Quickshell logs.

```bash
journalctl --user -u quickshell -n 30 --no-pager 2>/dev/null || echo "check quickshell stderr"
```

Expected: No QML errors referencing DockIcon.qml.

- [ ] **Step 3: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/DockIcon.qml
git commit -m "feat: DockIcon with Gaussian scale, Papirus icon, running dot, hover overlay"
```

---

## Task 3: Dock.qml — glass pill, pinned app list, icon row

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

- [ ] **Step 1: Replace Dock.qml with static layout (no autohide, no mouse tracking yet)**

`~/.config/quickshell/modules/dock/Dock.qml`:
```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../.."
import "../../overview/services"

PanelWindow {
    id: dock

    // ── Tunables ───────────────────────────────────────────────────────────
    readonly property int   iconSize:      48
    readonly property real  maxScale:      1.8
    readonly property real  spread:        2.2
    readonly property int   frameMs:       16
    readonly property int   triggerWidth:  320
    readonly property int   triggerHeight: 4
    readonly property int   iconSpacing:   10
    readonly property int   paddingH:      14
    readonly property int   paddingV:      12
    readonly property int   bottomGap:     10

    // ── Pinned apps — EDIT THIS ────────────────────────────────────────────
    readonly property var pinnedApps: [
        { class: "firefox",        exec: "firefox",     icon: "firefox"   },
        { class: "dev.zed.Zed",    exec: "zeditor",     icon: "zed"       },
        { class: "kitty",          exec: "kitty",        icon: "kitty"     },
        { class: "thunar",         exec: "thunar",       icon: "thunar"    },
        { class: "spotify",        exec: "spotify",      icon: "spotify"   },
    ]

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: true  // always visible for now
    property real dockMouseX:  -9999

    // ── App list (pinned only for now, running merge in Task 6) ───────────
    readonly property var mergedApps: pinnedApps.map(a => ({
        ...a, isRunning: false, isPinned: true
    }))

    // ── Dimensions ────────────────────────────────────────────────────────
    readonly property int dockBodyHeight: Math.ceil(iconSize * maxScale) + paddingV * 2 + 6
    readonly property int dockFullHeight: dockBodyHeight + bottomGap + triggerHeight
    readonly property int dockWidth: mergedApps.length * (iconSize + iconSpacing)
                                     - iconSpacing + paddingH * 2

    // ── Window ────────────────────────────────────────────────────────────
    anchors { bottom: true }
    implicitWidth:  Math.max(dockWidth, triggerWidth + paddingH * 2)
    implicitHeight: dockFullHeight
    exclusiveZone:  0
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

    // ── Launch helper ──────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        const p = procProto.createObject(dock, { command: cmd })
        p.running = true
    }

    // ── Dock body ──────────────────────────────────────────────────────────
    Item {
        id: dockBody
        width:  dock.dockWidth
        height: dock.dockBodyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0  // autohide animation added in Task 5

        // Glass pill background
        Rectangle {
            anchors.fill: parent
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Qt.rgba(Theme.surface_container.r,
                           Theme.surface_container.g,
                           Theme.surface_container.b, 0.72)
            border.color: Qt.rgba(Theme.outline_variant.r,
                                  Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.18)
            border.width: 1

            // Top-edge glass shine
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
                radius: parent.radius
            }
        }

        // Icon row
        Row {
            id: iconsRow
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            Repeater {
                model: dock.mergedApps
                DockIcon {
                    required property var  modelData
                    required property int  index
                    appData:      modelData
                    iconSize:     dock.iconSize
                    maxScale:     dock.maxScale
                    spread:       dock.spread
                    frameMs:      dock.frameMs
                    dockMouseX:   dock.dockMouseX
                    iconCenterX:  x + dock.iconSize / 2
                    onClicked: {
                        if (modelData.isRunning)
                            Hyprland.dispatch("focuswindow class:" + modelData.class)
                        else
                            dock.launch(["uwsm-app", "--", modelData.exec])
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Reload Quickshell and verify**

Reload Quickshell. Expected:
- A glass pill dock appears at the bottom center of the screen
- 5 icons visible (Firefox, Zed, Kitty, Thunar, Spotify)
- Icons load from Papirus-Dark; any missing show the fallback generic icon
- No running dots visible (isRunning is hardcoded false for now)
- Pill width matches the number of icons

- [ ] **Step 3: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "feat: dock glass pill layout with static pinned app icons"
```

---

## Task 4: Gaussian magnification

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

- [ ] **Step 1: Add mouse tracking MouseArea to dockBody in Dock.qml**

Inside the `Item { id: dockBody ... }` block, add after the `Row { id: iconsRow ... }`:

```qml
// Mouse tracking for Gaussian magnification
MouseArea {
    id: dockHoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    propagateComposedEvents: true
    onPositionChanged: mouse => {
        dock.dockMouseX = mapToItem(iconsRow, mouse.x, mouse.y).x
    }
    onExited: dock.dockMouseX = -9999
}
```

- [ ] **Step 2: Reload and test magnification**

Reload Quickshell. Move the mouse slowly across the dock.

Expected:
- Icons near the cursor grow smoothly (Gaussian bell curve effect)
- Icons far from cursor stay at normal size
- Scale transitions are smooth (exponential decay lerp, ~60fps)
- All icons return to scale 1.0 when mouse leaves dock

- [ ] **Step 3: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "feat: Gaussian spotlight magnification on dock hover"
```

---

## Task 5: Autohide

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

- [ ] **Step 1: Change dockVisible default to false and add hide timer**

In the `// ── State` section, change:
```qml
property bool dockVisible: true  // always visible for now
```
to:
```qml
property bool dockVisible: false
```

After the `dockMouseX` property, add:
```qml
readonly property bool anyFullscreen: {
    return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0)
}
onAnyFullscreenChanged: if (anyFullscreen) dockVisible = false
```

- [ ] **Step 2: Add Behavior on dockBody.y and trigger zone to Dock.qml**

Replace the `y: 0` line inside `Item { id: dockBody ... }` with:
```qml
y: dock.dockVisible ? 0 : dock.dockFullHeight
Behavior on y {
    NumberAnimation {
        duration: 220
        easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
    }
}
```

After the closing `}` of `Item { id: dockBody ... }`, add:

```qml
// ── Autohide trigger strip ─────────────────────────────────────────────
MouseArea {
    id: triggerZone
    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
    }
    width:  dock.triggerWidth
    height: dock.triggerHeight + 2
    hoverEnabled: true
    onEntered: {
        hideTimer.stop()
        dock.dockVisible = true
    }
}

// ── Hide delay timer ───────────────────────────────────────────────────
Timer {
    id: hideTimer
    interval: 350
    repeat: false
    onTriggered: dock.dockVisible = false
}
```

- [ ] **Step 3: Wire dockHoverArea to the hide timer**

In the existing `MouseArea { id: dockHoverArea ... }` block, update `onExited`:
```qml
onExited: {
    dock.dockMouseX = -9999
    hideTimer.restart()
}
```
And add `onEntered`:
```qml
onEntered: hideTimer.stop()
```

- [ ] **Step 4: Reload and test autohide**

Reload Quickshell. Expected:
- Dock is hidden at startup
- Moving mouse to the very bottom center (within the trigger strip) makes the dock slide up
- Moving mouse away from dock makes it slide back down after ~350ms delay
- Opening a fullscreen window makes the dock hide and stay hidden
- Closing the fullscreen window allows the dock to be triggered again

- [ ] **Step 5: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "feat: autohide with bottom-center trigger, fullscreen detection"
```

---

## Task 6: Running app detection and merge

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

- [ ] **Step 1: Replace the static mergedApps property with the live version**

Replace the existing `readonly property var mergedApps` block:
```qml
// ── App list (pinned only for now, running merge in Task 6) ───────────
readonly property var mergedApps: pinnedApps.map(a => ({
    ...a, isRunning: false, isPinned: true
}))
```

With:
```qml
// ── App list: pinned + running, deduplicated ───────────────────────────
readonly property var mergedApps: {
    const pinnedClasses = new Set(pinnedApps.map(a => a.class.toLowerCase()))
    const runningMap = {}
    HyprlandData.windowList.forEach(w => {
        const cls = (w.class || "").toLowerCase()
        if (cls && !runningMap[cls]) runningMap[cls] = w
    })

    const result = pinnedApps.map(app => ({
        class:     app.class,
        exec:      app.exec,
        icon:      app.icon,
        isRunning: !!runningMap[app.class.toLowerCase()],
        isPinned:  true
    }))

    Object.keys(runningMap).forEach(cls => {
        if (!pinnedClasses.has(cls)) {
            const w = runningMap[cls]
            const rawIcon = (w.class || "").toLowerCase().replace(/\./g, "-")
            result.push({
                class:     w.class,
                exec:      w.class.toLowerCase(),
                icon:      rawIcon,
                isRunning: true,
                isPinned:  false
            })
        }
    })

    return result
}
```

- [ ] **Step 2: Reload and verify running indicators**

Open Firefox, Kitty, or Spotify (any pinned app). Reload Quickshell. Trigger the dock.

Expected:
- Running pinned apps show a small dot below the icon
- Non-running pinned apps have no dot
- If you have a non-pinned app open (e.g. Discord), it appears appended at the end of the dock
- Dock width adjusts dynamically to the number of icons

- [ ] **Step 3: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "feat: live running app detection, dock icon list merges pinned + running"
```

---

## Task 7: Click to focus or launch

**Files:**
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

The click handler is already wired in Task 3. This task verifies it works correctly.

- [ ] **Step 1: Verify click on running app focuses it**

With a pinned app running (e.g. Firefox), trigger the dock and click the Firefox icon.

Expected: Firefox window receives focus. Dock hides after mouse leaves.

- [ ] **Step 2: Verify click on not-running pinned app launches it**

Click a pinned app that is not running (e.g. Spotify).

Expected: Spotify launches via `uwsm-app -- spotify`. The running indicator dot appears once Spotify starts and HyprlandData updates.

- [ ] **Step 3: Fix exec for any pinned app that doesn't launch correctly**

If a click doesn't launch the app, check the `exec` field in the `pinnedApps` array. For example, Zed's exec is `zeditor`, not `zed`. Update the array at the top of Dock.qml as needed.

- [ ] **Step 4: Commit (if exec fields were changed)**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "fix: correct exec commands for pinned apps"
```

---

## Task 8: Hyprland blur layerrule + IpcHandler

**Files:**
- Modify: `~/.config/hypr/source/windowrules.conf`
- Modify: `~/.config/quickshell/modules/dock/Dock.qml`

- [ ] **Step 1: Add layerrule for dock blur**

In `~/.config/hypr/source/windowrules.conf`, after the existing `quickshell_overview` layerrule block, add:

```conf
# Quickshell dock
layerrule {
    name            = quickshell_dock
    match:namespace = ^quickshell:dock$
    blur            = on
    ignore_alpha    = 0.05
}
```

- [ ] **Step 2: Reload Hyprland config**

```bash
hyprctl reload
```

Expected: Dock pill now blurs whatever is behind it. The glass effect becomes visible.

- [ ] **Step 3: Add IpcHandler to Dock.qml**

At the bottom of the `PanelWindow { id: dock ... }` block, before the closing `}`, add:

```qml
// ── IPC ────────────────────────────────────────────────────────────────
IpcHandler {
    target: "dock"
    function toggle() { dock.dockVisible = !dock.dockVisible }
    function show()   { dock.dockVisible = true }
    function hide()   { dock.dockVisible = false }
}
```

- [ ] **Step 4: Test IPC**

```bash
quickshell ipc call dock show
quickshell ipc call dock hide
quickshell ipc call dock toggle
```

Expected: Each command shows/hides/toggles the dock as described.

- [ ] **Step 5: Commit**

```bash
cd ~/.config/quickshell
git add modules/dock/Dock.qml
git commit -m "feat: IpcHandler for dock show/hide/toggle"

cd ~/.config/hypr
git add source/windowrules.conf
git commit -m "feat: add blur layerrule for quickshell:dock"
```

---

## Final Checklist

- [ ] Dock appears centered at bottom, floating, with correct width for app count
- [ ] Mouse hovering bottom-center activation strip slides dock up smoothly
- [ ] Mouse leaving dock slides it back down after ~350ms
- [ ] Fullscreen windows force-hide the dock
- [ ] Icons magnify with Gaussian falloff around cursor, animate at ~60fps
- [ ] Running indicator dots appear on pinned apps that are open
- [ ] Non-pinned running apps appear appended after pinned apps
- [ ] Clicking a running app focuses it; clicking a not-running app launches it
- [ ] Papirus-Dark icons load; generic fallback on error
- [ ] Dock blurs background (Hyprland blur layerrule active)
- [ ] `quickshell ipc call dock toggle` works
