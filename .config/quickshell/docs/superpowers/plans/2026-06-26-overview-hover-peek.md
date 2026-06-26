# Overview Hover Peek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add mouse-triggered hover peek popups to the workspace overview so users can inspect and click-to-focus individual windows without changing the Super+Tab keyboard flow.

**Architecture:** A single shared `WorkspacePeekPopup` in `OverviewWidget` positions above the hovered tile via `mapToItem`. Reuses `WorkspacePreview` + `WindowThumbnail` with a new `interactive` flag. Tiles emit hover signals with debounced show/hide timers.

**Tech Stack:** Quickshell 0.3 QML, `ScreencopyView`, existing `HyprlandData` / `HyprDispatch` focus path.

**Spec:** [`docs/superpowers/specs/2026-06-26-overview-hover-peek-design.md`](../specs/2026-06-26-overview-hover-peek-design.md)

---

## File map

| File | Responsibility |
|------|----------------|
| `overview/modules/overview/WindowThumbnail.qml` | Optional click-to-focus + hover highlight |
| `overview/modules/overview/WorkspacePreview.qml` | `interactive` flag + forward window clicks |
| `overview/modules/overview/WorkspaceTile.qml` | Hover signals with 150ms show delay |
| `overview/modules/overview/WorkspacePeekPopup.qml` | Positioned floating peek shell |
| `overview/modules/overview/OverviewWidget.qml` | Peek lifecycle, timers, capture override |
| `overview/modules/overview/qmldir` | Register peek component |

---

### Task 1: Interactive `WindowThumbnail`

**Files:**
- Modify: `.config/quickshell/overview/modules/overview/WindowThumbnail.qml`

- [ ] **Step 1: Add interactive property, signal, and click handler**

Add after existing properties:

```qml
property bool interactive: false
signal clicked(var windowData)

readonly property bool hovered: interactive && clickArea.containsMouse
```

Add after the fallback `Rectangle` block:

```qml
Rectangle {
    anchors.fill: parent
    radius: 3
    visible: root.interactive && root.hovered
    color: "transparent"
    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.75)
    border.width: 2
    z: 2
}

MouseArea {
    id: clickArea

    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: root.interactive
    cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    z: 3
    onClicked: root.clicked(root.windowData)
}
```

- [ ] **Step 2: Reload shell and smoke-check overview still opens**

```bash
qs -n -d &
quickshell ipc call overview toggle
quickshell ipc call overview toggle
```

Expected: overview opens/closes with no QML errors in journal.

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/overview/modules/overview/WindowThumbnail.qml
git commit -m "feat(overview): add interactive click support to WindowThumbnail"
```

---

### Task 2: Interactive `WorkspacePreview`

**Files:**
- Modify: `.config/quickshell/overview/modules/overview/WorkspacePreview.qml`

- [ ] **Step 1: Add interactive property and signal**

After `property int cornerRadius: 10`:

```qml
property bool interactive: false
signal requestFocusWindow(var windowData)
```

- [ ] **Step 2: Pass interactive to delegates and wire clicks**

In the `WindowThumbnail` delegate, add:

```qml
interactive: root.interactive
onClicked: windowData => root.requestFocusWindow(windowData)
```

- [ ] **Step 3: Reload and verify overview tiles unchanged**

```bash
quickshell ipc call overview toggle
```

Expected: tiles render as before; no regressions.

- [ ] **Step 4: Commit**

```bash
git add .config/quickshell/overview/modules/overview/WorkspacePreview.qml
git commit -m "feat(overview): forward window clicks from WorkspacePreview"
```

---

### Task 3: Hover signals on `WorkspaceTile`

**Files:**
- Modify: `.config/quickshell/overview/modules/overview/WorkspaceTile.qml`

- [ ] **Step 1: Add peek signals and show timer**

After existing signals:

```qml
signal peekRequested()
signal peekDismissed()
```

Replace the existing bottom `MouseArea` with:

```qml
Timer {
    id: peekShowTimer

    interval: 150
    repeat: false
    onTriggered: root.peekRequested()
}

MouseArea {
    id: tileMouseArea

    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: peekShowTimer.restart()
    onExited: {
        peekShowTimer.stop()
        root.peekDismissed()
    }
    onClicked: root.requestWorkspace(root.workspaceId)
}
```

- [ ] **Step 2: Reload overview — hover should not error (peek not wired yet)**

```bash
quickshell ipc call overview toggle
```

Expected: tile click still switches workspace; no QML errors on hover.

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/overview/modules/overview/WorkspaceTile.qml
git commit -m "feat(overview): emit hover peek signals from WorkspaceTile"
```

---

### Task 4: Create `WorkspacePeekPopup`

**Files:**
- Create: `.config/quickshell/overview/modules/overview/WorkspacePeekPopup.qml`
- Modify: `.config/quickshell/overview/modules/overview/qmldir`

- [ ] **Step 1: Register in qmldir**

Add line:

```
WorkspacePeekPopup 1.0 WorkspacePeekPopup.qml
```

- [ ] **Step 2: Create `WorkspacePeekPopup.qml`**

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../../"

Item {
    id: root

    required property var anchorItem
    required property int workspaceId
    required property var windows
    required property var monitorData
    required property var toplevelByAddress
    required property bool overviewActive
    required property bool active
    required property bool selected
    required property int outerMargin

    signal requestFocusWindow(var windowData)
    signal peekEntered()
    signal peekExited()

    readonly property int labelStripHeight: 22
    readonly property int previewInset: 8
    readonly property int cornerRadius: 16
    readonly property int previewRadius: 10
    readonly property int gap: 10
    readonly property real peekScale: 2.2

    readonly property real anchorX: anchorItem ? anchorItem.mapToItem(root.parent, 0, 0).x : 0
    readonly property real anchorY: anchorItem ? anchorItem.mapToItem(root.parent, 0, 0).y : 0
    readonly property real anchorW: anchorItem ? anchorItem.width : 0
    readonly property real anchorH: anchorItem ? anchorItem.height : 0

    readonly property int peekWidth: {
        if (!anchorItem)
            return 0;
        const maxW = root.parent.width - outerMargin * 2;
        return Math.min(Math.round(anchorW * peekScale), maxW);
    }

    readonly property int peekHeight: {
        if (!anchorItem)
            return 0;
        const previewH = anchorH - labelStripHeight;
        const maxH = root.parent.height - outerMargin * 2;
        return Math.min(Math.round(previewH * peekScale) + labelStripHeight, maxH);
    }

    readonly property bool placeBelow: {
        const aboveY = anchorY - peekHeight - gap;
        return aboveY < outerMargin;
    }

    readonly property real posX: {
        let x = anchorX + (anchorW - peekWidth) / 2;
        x = Math.max(outerMargin, x);
        x = Math.min(x, root.parent.width - peekWidth - outerMargin);
        return x;
    }

    readonly property real posY: placeBelow
        ? anchorY + anchorH + gap
        : anchorY - peekHeight - gap

    visible: anchorItem !== null && peekWidth > 0 && peekHeight > 0
    x: posX
    y: posY
    width: peekWidth
    height: peekHeight
    z: 100

    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.92
    transformOrigin: placeBelow ? Item.Top : Item.Bottom

    Behavior on opacity {
        enabled: Perf.animationsEnabled
        NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        enabled: Perf.animationsEnabled
        NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
    }

    RectangularShadow {
        anchors.fill: card
        radius: root.cornerRadius
        blur: 48
        spread: 2
        offset: Qt.vector2d(0, 6)
        color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.18)
        cached: true
        z: -1
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.selected
            ? Qt.tint(Theme.glassSection, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
            : root.active
                ? Theme.glassSectionHigh
                : Theme.glassSection
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
        border.width: 1
        antialiasing: true
        clip: true

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: root.height - root.labelStripHeight

                WorkspacePreview {
                    anchors.fill: parent
                    anchors.margins: root.previewInset
                    cornerRadius: root.previewRadius
                    windows: root.windows ?? []
                    monitorData: root.monitorData
                    toplevelByAddress: root.toplevelByAddress
                    overviewActive: root.overviewActive
                    tileCaptureActive: true
                    interactive: true
                    onRequestFocusWindow: windowData => root.requestFocusWindow(windowData)
                }
            }

            Rectangle {
                width: parent.width
                height: root.labelStripHeight
                radius: root.cornerRadius
                color: Theme.glassSectionHigh

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: root.cornerRadius
                    color: parent.color
                }

                Text {
                    anchors.centerIn: parent
                    text: "WORKSPACE " + root.workspaceId
                    color: root.active ? Theme.primary : Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.peekEntered()
        onExited: root.peekExited()
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/overview/modules/overview/WorkspacePeekPopup.qml \
        .config/quickshell/overview/modules/overview/qmldir
git commit -m "feat(overview): add WorkspacePeekPopup component"
```

---

### Task 5: Wire peek lifecycle in `OverviewWidget`

**Files:**
- Modify: `.config/quickshell/overview/modules/overview/OverviewWidget.qml`

- [ ] **Step 1: Add peek state, timers, and helpers**

After `signal requestCloseWorkspace`:

```qml
property int peekWorkspaceId: -1
property var peekAnchorItem: null
property bool peekPointerInside: false

function hidePeekImmediate() {
    peekHideTimer.stop();
    peekWorkspaceId = -1;
    peekAnchorItem = null;
    peekPointerInside = false;
}

function showPeekForTile(workspaceId, tileItem) {
    peekHideTimer.stop();
    peekWorkspaceId = workspaceId;
    peekAnchorItem = tileItem;
}

function scheduleHidePeek() {
    if (peekPointerInside)
        return;
    peekHideTimer.restart();
}
```

Update `tileCaptureActive`:

```qml
function tileCaptureActive(workspaceId) {
    if (!overviewActive)
        return false;
    if (peekWorkspaceId === workspaceId)
        return true;
    if (!Perf.lightweightOverview)
        return true;
    return workspaceId === selectedWorkspaceId || workspaceId === activeWorkspaceId();
}
```

Extend `onOverviewActiveChanged`:

```qml
onOverviewActiveChanged: {
    if (overviewActive)
        Hyprland.refreshToplevels();
    else
        hidePeekImmediate();
}
```

Add timers after helper functions:

```qml
Timer {
    id: peekHideTimer
    interval: 200
    repeat: false
    onTriggered: root.hidePeekImmediate()
}
```

- [ ] **Step 2: Wire tile hover signals in delegate**

In `WorkspaceTile` delegate, add:

```qml
onPeekRequested: {
    root.showPeekForTile(modelData, /* tile reference — use id on tile */);
}
onPeekDismissed: root.scheduleHidePeek()
```

Because the delegate has no id, assign one:

```qml
delegate: WorkspaceTile {
    id: tileItem
    // ... existing bindings ...
    onPeekRequested: root.showPeekForTile(modelData, tileItem)
    onPeekDismissed: root.scheduleHidePeek()
}
```

- [ ] **Step 3: Hide peek on Flickable scroll**

In `workspacesScroller`:

```qml
onMovementStarted: root.hidePeekImmediate()
onContentYChanged: {
    if (moving || flicking)
        root.hidePeekImmediate();
}
```

- [ ] **Step 4: Add `WorkspacePeekPopup` sibling above panel**

After the closing `}` of `panel` Rectangle (still inside root `Item`), add:

```qml
WorkspacePeekPopup {
    id: workspacePeek

    anchors.fill: parent
    outerMargin: root.panelOuterMargin
    anchorItem: root.peekAnchorItem
    workspaceId: root.peekWorkspaceId
    windows: root.peekWorkspaceId > 0 ? root.windowsForWorkspace(root.peekWorkspaceId) : []
    monitorData: root.peekWorkspaceId > 0 ? root.monitorForWorkspace(root.peekWorkspaceId) : null
    toplevelByAddress: root.toplevelByAddress
    overviewActive: root.overviewActive
    active: root.peekWorkspaceId === root.activeWorkspaceId()
    selected: root.peekWorkspaceId === root.selectedWorkspaceId
    visible: root.peekAnchorItem !== null && root.peekWorkspaceId > 0

    onRequestFocusWindow: windowData => root.requestFocusWindow(windowData)
    onPeekEntered: {
        root.peekPointerInside = true;
        root.peekHideTimer.stop();
    }
    onPeekExited: {
        root.peekPointerInside = false;
        root.scheduleHidePeek();
    }
}
```

- [ ] **Step 5: Manual test hover peek**

```bash
quickshell ipc call overview toggle
```

Manual checks:
- Hover tile ≥150ms → peek appears above tile
- Move into peek → stays open
- Leave tile + peek → peek dismisses
- Click window in peek → window focused, overview closes
- Click tile → workspace switches
- Scroll panel → peek hides

- [ ] **Step 6: Commit**

```bash
git add .config/quickshell/overview/modules/overview/OverviewWidget.qml
git commit -m "feat(overview): wire hover peek lifecycle in OverviewWidget"
```

---

### Task 6: Update spec status + final verification

**Files:**
- Modify: `.config/quickshell/docs/superpowers/specs/2026-06-26-overview-hover-peek-design.md`

- [ ] **Step 1: Mark spec approved**

Change header line:

```markdown
**Status:** Approved (lgtm 2026-06-26)
```

- [ ] **Step 2: Run full manual checklist from spec**

```bash
quickshell ipc call overview toggle
journalctl --user -u quickshell -n 30 --no-pager
```

Verify all spec manual test items:
- Hover tile → peek above (or below near top edge)
- Peek clamped horizontally at screen edges
- Super+Tab cycle → no peek
- Lightweight overview ON → peek still live-captures hovered workspace
- Overview close → peek gone

- [ ] **Step 3: Commit**

```bash
git add .config/quickshell/docs/superpowers/specs/2026-06-26-overview-hover-peek-design.md
git commit -m "docs: mark overview hover peek spec approved"
```

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| 150ms hover show delay | Task 3 |
| 200ms hide delay + peek hover bridge | Task 5 |
| Click window → focus + close overview | Tasks 1–2, 5 (existing Overview.qml path) |
| Click tile → switch workspace | Task 3 (unchanged click) |
| Keyboard flow unchanged | No keyboard hooks added |
| Shared popup at widget level | Tasks 4–5 |
| Above/below flip + horizontal clamp | Task 4 |
| ~2.2× peek scale | Task 4 |
| Lightweight overview exception for peek | Task 5 `tileCaptureActive` |
| Hide on scroll / overview close | Task 5 |
| Max 8 windows | Task 4 reuses `WorkspacePreview.windowsToShow` |

---

## Self-review notes

- No automated QML tests exist in this repo; manual IPC + hover checks substitute for TDD steps (same pattern as 2026-06-11 plan).
- `WorkspacePeekPopup` uses `mapToItem(root.parent, …)` — parent must be full-screen `OverviewWidget` Item (matches Task 5 wiring).
- Tile clicks still work when peek floats above — peek is positioned above/below tile, not over it, so workspace switch clicks are unobstructed.
