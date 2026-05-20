# Dynamic Island — Implementation Spec
**Date:** 2026-05-20  
**Status:** Approved — ready for implementation

---

## What you are building

Replace `NotificationPopups.qml` with an iOS Dynamic Island–style pill that appears below the top bar, centered horizontally. The island is a general-purpose platform — any module can push a timed "activity" widget into it. Notifications are the first activity. Future activities (timers, media, etc.) are new files that slot in without touching the island shell.

---

## Files — create / modify / delete

| Action | Path (relative to `.config/quickshell/`) |
|--------|------------------------------------------|
| CREATE | `modules/island/qmldir` |
| CREATE | `modules/island/DynamicIslandService.qml` |
| CREATE | `modules/island/DynamicIsland.qml` |
| CREATE | `modules/island/NotificationActivity.qml` |
| MODIFY | `shell.qml` |
| DELETE | `NotificationPopups.qml` |

---

## File 1 — `modules/island/qmldir`

```
module modules.island
singleton DynamicIslandService 1.0 DynamicIslandService.qml
DynamicIsland 1.0 DynamicIsland.qml
NotificationActivity 1.0 NotificationActivity.qml
```

This registers `DynamicIslandService` as a QML singleton so any file can access it by importing the module.

---

## File 2 — `modules/island/DynamicIslandService.qml`

This is the activity bus. It holds the queue and owns the auto-dismiss timer. The island shell and any module that wants to push content both talk to this singleton.

```qml
pragma Singleton

import QtQuick

QtObject {
    id: root

    // ── Public: read by the island shell ─────────────────────────────────────
    property var  currentActivity: null   // the activity currently showing, or null
    property int  pendingCount:    0      // how many are queued behind current

    // ── Public: emitted when the current activity's time is up ───────────────
    // The island shell connects to this and starts the exit animation.
    signal exitRequested()

    // ── Internal ──────────────────────────────────────────────────────────────
    property var  _queue:  []    // array of activity objects waiting their turn
    property int  _serial: 0    // increments to generate unique ids

    // Auto-dismiss timer. Fires when current activity's durationMs elapses.
    property var _timer: Timer {
        repeat:   false
        running:  false
        onTriggered: root.exitRequested()
    }

    // ── push(activityDef) → id ────────────────────────────────────────────────
    // activityDef shape:
    //   {
    //     contentComponent: Component,  // QML Component to Loader.sourceComponent
    //     priority:         int,        // higher = closer to front of queue
    //     durationMs:       int,        // 0 = never auto-dismiss
    //     data:             object      // passed through to the content component
    //   }
    // Returns the id string assigned to this activity.
    function push(activityDef) {
        const id = "activity-" + root._serial++;
        const activity = {
            id:               id,
            contentComponent: activityDef.contentComponent,
            priority:         activityDef.priority  ?? 10,
            durationMs:       activityDef.durationMs ?? 5000,
            data:             activityDef.data       ?? {}
        };

        if (root.currentActivity === null) {
            // Nothing showing — make this current immediately.
            root.currentActivity = activity;
            root._startTimer(activity.durationMs);
        } else {
            // Something is showing — extend its timeout and enqueue the new one.
            root._extendCurrent();
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
        }

        return id;
    }

    // ── remove(id) ────────────────────────────────────────────────────────────
    // Dismisses the activity with this id.
    // If it is currently showing  → emit exitRequested() so the island animates out.
    // If it is in the queue       → splice it out silently.
    function remove(id) {
        if (root.currentActivity && root.currentActivity.id === id) {
            root._timer.stop();
            root.exitRequested();
            return;
        }
        root._queue = root._queue.filter(a => a.id !== id);
        root.pendingCount = root._queue.length;
    }

    // ── popCurrent() ──────────────────────────────────────────────────────────
    // Called by the island shell AFTER the pill-out animation completes.
    // Promotes the next queued activity (if any) to currentActivity.
    function popCurrent() {
        root._timer.stop();
        if (root._queue.length > 0) {
            // Sort by priority desc, then promote first item.
            root._queue.sort((a, b) => b.priority - a.priority);
            root.currentActivity = root._queue.shift();
            root.pendingCount    = root._queue.length;
            root._startTimer(root.currentActivity.durationMs);
        } else {
            root.currentActivity = null;
            root.pendingCount    = 0;
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    function _startTimer(durationMs) {
        if (durationMs > 0) {
            root._timer.interval = durationMs;
            root._timer.restart();
        }
    }

    function _extendCurrent() {
        if (root.currentActivity && root.currentActivity.durationMs > 0)
            root._timer.restart();
    }

    function _insertQueued(activity) {
        const q = root._queue.slice();
        q.push(activity);
        q.sort((a, b) => b.priority - a.priority);
        root._queue = q;
    }
}
```

---

## File 3 — `modules/island/DynamicIsland.qml`

The shell. Owns the pill shape, all animations, and the state machine. Has zero knowledge of what activities contain — it just loads the component and sizes itself to fit.

### State machine

The island moves through these states in strict order:

```
idle → pill-in → expanding → visible → contracting → pill-out → idle
                                                              ↘ pill-in  (if queue non-empty)
```

| State | Entry condition | What runs |
|-------|-----------------|-----------|
| `"idle"` | startup, or `popCurrent()` with empty queue | Window hidden. Loader inactive. |
| `"pill-in"` | `currentActivity` becomes non-null | Loader activated. Pill scales 0 → 1. |
| `"expanding"` | pill-in scale animation finishes AND `Loader.status === Loader.Ready` | Pill width/height animate to content size + padding. |
| `"visible"` | expanding animations finish | Content fades in. Service timer is already running. |
| `"contracting"` | `DynamicIslandService.exitRequested()` fires | Content fades out. Pill width/height animate back to pillWidth/pillHeight. |
| `"pill-out"` | contracting animations finish | Pill scales 1 → 0. On complete: call `DynamicIslandService.popCurrent()`. |

After `popCurrent()`:
- If `currentActivity` is now non-null → set state to `"pill-in"` (next activity)
- If `currentActivity` is null → set state to `"idle"`

### Full file

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "." as QuickIsland

PanelWindow {
    id: island

    // ── Tunables ──────────────────────────────────────────────────────────────
    // islandPadding: space between the pill edge and the content inside it.
    // Every activity's implicitWidth/implicitHeight is the CONTENT size.
    // The pill becomes (implicitWidth + islandPadding*2) × (implicitHeight + islandPadding*2).
    readonly property int islandPadding: 10

    // pillWidth / pillHeight: size of the tiny pill during pill-in and pill-out.
    readonly property int pillWidth:  120
    readonly property int pillHeight:  28

    // pillRadius: border-radius of the pill. Keep high for fully rounded ends.
    readonly property int pillRadius:  20

    // These must match Bar.qml exactly.
    readonly property int barHeight:   40
    readonly property int barTopGap:    6

    // Gap between the bottom of the bar and the top of the island.
    readonly property int belowBarGap:  8

    // ── State ─────────────────────────────────────────────────────────────────
    property string islandState: "idle"   // "idle" | "pill-in" | "expanding" | "visible" | "contracting" | "pill-out"

    // Computed target size for the expanded pill. Read from content after it loads.
    property real targetWidth:  pillWidth
    property real targetHeight: pillHeight

    // ── Window setup ─────────────────────────────────────────────────────────
    // anchors.top only (no left/right) → compositor centers the window horizontally.
    anchors.top: true
    margins.top: barHeight + barTopGap + belowBarGap

    // Window tracks the pill size so it never clips the pill during animation.
    implicitWidth:  pill.width
    implicitHeight: pill.height

    exclusiveZone: 0
    color:         "transparent"

    // Hide the window entirely when idle. Keeps it out of compositor hit-testing.
    visible: islandState !== "idle"

    WlrLayershell.layer:     WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:island"

    // ── Service connection ────────────────────────────────────────────────────
    Connections {
        target: QuickIsland.DynamicIslandService
        function onExitRequested() {
            island.islandState = "contracting";
        }
        function onCurrentActivityChanged() {
            // Fires after popCurrent() promotes next activity OR clears to null.
            if (island.islandState === "idle" && QuickIsland.DynamicIslandService.currentActivity !== null) {
                island.islandState = "pill-in";
            }
        }
    }

    // ── State machine driver ──────────────────────────────────────────────────
    onIslandStateChanged: {
        switch (islandState) {

        case "pill-in":
            // Activate the loader NOW so it loads while the pill animates in.
            // The pill-in animation runs; expanding starts only when BOTH the
            // scale animation finishes AND Loader.status === Ready.
            contentLoader.active = true;
            pill.scale = 0;
            pillScaleInAnim.start();
            break;

        case "expanding":
            // Read content's natural size. The Loader item fills the island
            // minus islandPadding on each side, so content declares its own
            // implicitWidth/implicitHeight and the island sizes to match.
            island.targetWidth  = contentLoader.item.implicitWidth  + island.islandPadding * 2;
            island.targetHeight = contentLoader.item.implicitHeight + island.islandPadding * 2;
            pillExpandWidthAnim.start();
            pillExpandHeightAnim.start();
            break;

        case "visible":
            contentOpacityInAnim.start();
            break;

        case "contracting":
            contentOpacityOutAnim.start();
            pillContractWidthAnim.start();
            pillContractHeightAnim.start();
            break;

        case "pill-out":
            pillScaleOutAnim.start();
            break;

        case "idle":
            contentLoader.active = false;
            pill.scale = 0;
            break;
        }
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: pill

        // width/height start at pillWidth/pillHeight; state machine animates them.
        width:  island.pillWidth
        height: island.pillHeight
        radius: island.pillRadius
        scale:  0   // starts invisible; animated by pill-in / pill-out

        // Color: check urgency from current activity's data.
        // urgency 2 = critical → use error color. Otherwise surface_container.
        color: {
            const d = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
            return (d.urgency === 2)
                ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.95)
                : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.96)
        }

        border.width: 1
        border.color: {
            const d = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
            return (d.urgency === 2)
                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7)
                : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
        }

        // ── Content loader ────────────────────────────────────────────────────
        Loader {
            id: contentLoader
            anchors.fill:    parent
            anchors.margins: island.islandPadding
            active:          false
            opacity:         0   // faded in during "visible" state

            sourceComponent: QuickIsland.DynamicIslandService.currentActivity?.contentComponent ?? null

            // Forward data to the loaded item once it's ready.
            onStatusChanged: {
                if (status === Loader.Ready) {
                    item.data = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
                    // If we're still in pill-in (scale anim may have already finished),
                    // try to advance. The flag below handles the race.
                    island._onLoaderReady();
                }
            }
        }

        // ── +N pending badge ──────────────────────────────────────────────────
        // Shows how many activities are queued behind the current one.
        // Sits in the top-right of the pill, above the content (z-ordered on top).
        // Safe to overlap because all activities are left-aligned inside the pill.
        Text {
            visible: QuickIsland.DynamicIslandService.pendingCount > 0
                  && island.islandState === "visible"
            text:   "+" + QuickIsland.DynamicIslandService.pendingCount
            color:  Qt.rgba(Theme.on_surface_variant.r,
                            Theme.on_surface_variant.g,
                            Theme.on_surface_variant.b, 0.8)
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 9

            anchors.right:          parent.right
            anchors.rightMargin:    island.islandPadding
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Race-condition guard ──────────────────────────────────────────────────
    // pill-in scale anim and Loader load are both async. We advance to "expanding"
    // only when BOTH have finished. These flags track each side.
    property bool _pillInDone:   false
    property bool _loaderReady:  false

    function _tryAdvanceToExpanding() {
        if (_pillInDone && _loaderReady) {
            _pillInDone  = false;
            _loaderReady = false;
            islandState  = "expanding";
        }
    }
    function _onPillInDone() {
        _pillInDone = true;
        _tryAdvanceToExpanding();
    }
    function _onLoaderReady() {
        if (islandState !== "pill-in") return;  // guard stale signals
        _loaderReady = true;
        _tryAdvanceToExpanding();
    }

    // ── Animations ────────────────────────────────────────────────────────────

    // pill-in: tiny pill springs into existence
    NumberAnimation {
        id:       pillScaleInAnim
        target:   pill
        property: "scale"
        from:     0; to: 1
        duration: 150
        easing.type: Easing.OutBack
        easing.overshoot: 1.5
        onFinished: island._onPillInDone()
    }

    // expanding: pill grows to content size
    NumberAnimation {
        id:       pillExpandWidthAnim
        target:   pill
        property: "width"
        to:       island.targetWidth
        duration: 250
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id:       pillExpandHeightAnim
        target:   pill
        property: "height"
        to:       island.targetHeight
        duration: 250
        easing.type: Easing.OutCubic
        onFinished: island.islandState = "visible"   // height anim is authoritative
    }

    // visible: content fades in
    NumberAnimation {
        id:       contentOpacityInAnim
        target:   contentLoader
        property: "opacity"
        from:     0; to: 1
        duration: 120
        easing.type: Easing.OutQuad
    }

    // contracting: content fades out, pill shrinks back to tiny pill
    NumberAnimation {
        id:       contentOpacityOutAnim
        target:   contentLoader
        property: "opacity"
        from:     1; to: 0
        duration: 120
        easing.type: Easing.InQuad
    }
    NumberAnimation {
        id:       pillContractWidthAnim
        target:   pill
        property: "width"
        to:       island.pillWidth
        duration: 200
        easing.type: Easing.InCubic
    }
    NumberAnimation {
        id:       pillContractHeightAnim
        target:   pill
        property: "height"
        to:       island.pillHeight
        duration: 200
        easing.type: Easing.InCubic
        onFinished: island.islandState = "pill-out"  // height anim is authoritative
    }

    // pill-out: tiny pill shrinks to nothing
    NumberAnimation {
        id:       pillScaleOutAnim
        target:   pill
        property: "scale"
        from:     1; to: 0
        duration: 150
        easing.type: Easing.InBack
        easing.overshoot: 1.5
        onFinished: {
            // Tell the service to pop current and promote next.
            QuickIsland.DynamicIslandService.popCurrent();
            // onCurrentActivityChanged in the Connections block handles
            // whether to go to pill-in or idle.
            if (QuickIsland.DynamicIslandService.currentActivity === null)
                island.islandState = "idle";
        }
    }
}
```

---

## File 4 — `modules/island/NotificationActivity.qml`

The notification content widget. The island Loader sets `item.data` after loading. This file only cares about laying out app name + summary. It declares its own `implicitWidth` and `implicitHeight` — the island sizes itself to fit these values.

**Content it receives via `data`:**
```js
{
  appName: string,   // e.g. "Firefox" — displayed in small caps above summary
  summary: string,   // e.g. "Download complete" — displayed bold below appName
  urgency: int       // 0=low, 1=normal, 2=critical — used by the pill for border color
}
```

**Layout (left to right):**
```
[ icon glyph 28×28 ]  [ column: APP NAME (9px, caps) ]
                      [         Summary (12px, bold)  ]
```

**Sizing rules:**
- `implicitWidth: 320` — fixed. Summary elides if longer.
- `implicitHeight: 28` — matches the icon height. Single height for all notifications.

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    // data is set by DynamicIsland.qml after Loader finishes.
    // Declare it here so the Loader can do: item.data = activity.data
    property var data: ({ appName: "", summary: "", urgency: 1 })

    implicitWidth:  320
    implicitHeight: 28

    RowLayout {
        anchors.fill: parent
        spacing: 10

        // App icon placeholder — nerd font bell glyph.
        // Replace with real app icon lookup in a future enhancement.
        Rectangle {
            width:  28
            height: 28
            radius: 8
            color:  Qt.rgba(Theme.surface_container_high.r,
                            Theme.surface_container_high.g,
                            Theme.surface_container_high.b, 0.6)
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text:             "󰂚"   // nf-md-bell
                color:            Theme.on_surface_variant
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   15
            }
        }

        // Text column
        ColumnLayout {
            Layout.fillWidth:   true
            Layout.alignment:   Qt.AlignVCenter
            spacing: 3

            // App name — small, uppercase
            Text {
                Layout.fillWidth: true
                text:             root.data.appName !== "" ? root.data.appName.toUpperCase() : "NOTIFICATION"
                color:            Theme.on_surface_variant
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   9
                font.letterSpacing: 0.8
                elide:            Text.ElideRight
            }

            // Summary — bold, main content
            Text {
                Layout.fillWidth: true
                text:             root.data.summary
                color:            Theme.on_surface
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   12
                font.weight:      Font.Bold
                elide:            Text.ElideRight
            }
        }
    }
}
```

---

## File 5 — `shell.qml` changes

### 1. Add import at the top (with other module imports)

```qml
import "modules/island" as QuickIsland
```

### 2. Remove the NotificationPopups instance

Delete this block entirely:

```qml
NotificationPopups {
    id: notifPopups
    notifServer: notifServer
}
```

### 3. Add the DynamicIsland window instance (in the same location)

```qml
QuickIsland.DynamicIsland {}
```

### 4. Add a Component for the notification activity (declare near the top of ShellRoot, with other properties)

```qml
Component {
    id: notifActivityComponent
    QuickIsland.NotificationActivity {}
}
```

### 5. Update the NotificationServer.onNotification handler

Replace:

```qml
onNotification: notif => {
    if (root.dnd) {
        notif.expire();
        return;
    }

    notif.tracked = true;

    if (notif.lastGeneration)
        return;
    const popupKey = notifPopups.enqueueNotification(notif);
    notif.closed.connect(() => notifPopups.removePopup(popupKey));
}
```

With:

```qml
onNotification: notif => {
    if (root.dnd) {
        notif.expire();
        return;
    }

    notif.tracked = true;

    if (notif.lastGeneration)
        return;

    const id = QuickIsland.DynamicIslandService.push({
        contentComponent: notifActivityComponent,
        priority:         10,
        durationMs:       notif.expireTimeout > 0
                              ? Math.min(Math.round(notif.expireTimeout * 1000), 5000)
                              : 5000,
        data: {
            appName: notif.appName || "",
            summary: notif.summary || "",
            urgency: notif.urgency
        }
    });
    notif.closed.connect(() => QuickIsland.DynamicIslandService.remove(id));
}
```

---

## File 6 — Delete `NotificationPopups.qml`

Delete the file at `.config/quickshell/NotificationPopups.qml`. It is fully replaced by the island system. Do not leave it in the repo.

---

## Dynamic sizing contract (for future activity authors)

Every activity component (`*Activity.qml`) **must**:

1. Declare `property var data: ({})` — the island sets this after load
2. Set `implicitWidth` to the desired content width (number, not `parent.width`)
3. Set `implicitHeight` to the desired content height (number, not `parent.height`)
4. **Never** hardcode `width` or `height` — the Loader drives those from the island
5. Use `parent.width` / `parent.height` for any children that should fill the available space

The island calculates its pill size as:
```
pill.width  = activity.implicitWidth  + islandPadding * 2   (default: implicitWidth + 20)
pill.height = activity.implicitHeight + islandPadding * 2   (default: implicitHeight + 20)
```

---

## What is explicitly out of scope for this implementation

- `NotifPanel.qml` — do not touch it; the notification center is unaffected
- App icon fetching — the bell glyph placeholder is intentional for now
- Click/interaction on the island — no tap handler for v1
- Multi-monitor — island appears on the primary screen only (same as current popups; `screen` property not set on the PanelWindow)
