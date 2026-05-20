# Dynamic Island — Design Spec
**Date:** 2026-05-20
**Status:** Approved

---

## Overview

Replace `NotificationPopups.qml` with an iOS Dynamic Island–style notch that lives below the top bar, centered horizontally. The island is a **general-purpose platform** — it hosts activity widgets from any module. Notifications are its first tenant; future widgets (timers, media, etc.) slot in without touching the island shell.

---

## Behaviour

### Position
- Floats below the top bar with a small gap (not overlapping it)
- Centered horizontally (`anchors { top: true }` only — no left/right anchors)
- `WlrLayershell.layer: Overlay`, `exclusiveZone: 0`

### Idle state
- Nothing visible when no activity is active
- The island PanelWindow is always present in the compositor but fully transparent and non-interactive when idle

### Entry animation (pill-in → expand)
1. Tiny pill (≈120×28 px) scales in from 0 — `Easing.OutBack` spring overshoot (~150 ms)
2. Pill width/height animate to content's natural size + padding — `Easing.OutCubic` (~250 ms)
3. Content `Loader` fades in after expand completes

### Exit animation (contract → pill-out) — mirror of entry
1. Content fades out
2. Pill width/height contract back to tiny pill — `Easing.InCubic` (~200 ms)
3. Tiny pill scales to 0 — `Easing.InBack` (~150 ms)
4. Current activity is popped; if the queue is non-empty, the next activity begins from step 1 of entry

### Multiple activities (queue with extend)
When `push()` is called while an activity is already showing:
- The current activity's timeout is reset (extended)
- The new activity joins the queue ordered by priority (higher first), then FIFO within the same priority
- A `+N` badge appears right-aligned inside the island showing how many are queued
- Activities are never interrupted mid-display; the queue drains one at a time

---

## Dynamic sizing contract

The island has **no hardcoded expanded dimensions**. Each activity component declares its own `implicitWidth` / `implicitHeight`. The island animates to:

```
island width  = loader.item.implicitWidth  + islandPadding * 2
island height = loader.item.implicitHeight + islandPadding * 2
```

`islandPadding` is a single tunable at the top of `DynamicIsland.qml` (default: `10`).

The `Loader` item is anchored `fill: parent` with `anchors.margins: islandPadding`, so every activity receives exactly `(islandWidth - padding*2)` to work with. Activities must not hardcode their own width — they should use `implicitWidth`/`implicitHeight` to declare their natural size and let the parent drive their actual bounds.

---

## File structure

```
modules/island/
  DynamicIslandService.qml   — singleton activity bus
  DynamicIsland.qml          — shell: pill shape + state machine + animations
  NotificationActivity.qml   — notification content widget (first tenant)
```

`NotificationPopups.qml` is deleted.

---

## `DynamicIslandService.qml`

**Type:** `QtObject` singleton (same pattern as `TimerService`)

### Activity object schema
```js
{
  id:               string,     // auto-generated serial ("activity-0", "activity-1", …)
  contentComponent: Component,  // QML Component to load inside the island
  priority:         int,        // higher = sorted toward front of queue; notifications = 10
  durationMs:       int,        // auto-dismiss after this many ms; 0 = manual dismiss only
  data:             object      // arbitrary payload forwarded to the content component
}
```

### Public API
| Member | Description |
|--------|-------------|
| `push(activity) → id` | Enqueue an activity. Returns its id. |
| `remove(id)` | Dismiss a specific activity by id (works on current or queued). |
| `extendCurrent()` | Reset the timeout on the currently showing activity. |
| `readonly currentActivity` | The activity being shown now, or `null`. |
| `readonly pendingCount` | Count of activities queued behind current. |

### Internal behaviour
- `push()` on an empty queue: sets `currentActivity` immediately, starts the timer
- `push()` while showing: calls `extendCurrent()`, inserts new activity into queue sorted by priority desc
- Timer fires: triggers the island's exit animation; on animation complete, service pops `currentActivity` and promotes next from queue
- `remove(id)` on current: triggers exit animation immediately; `remove(id)` on queued: splice from queue

---

## `DynamicIsland.qml`

**Type:** `PanelWindow`

### Tunables (top of file)
```qml
readonly property int islandPadding:   10
readonly property int pillWidth:      120
readonly property int pillHeight:      28
readonly property int pillRadius:      20  // fully rounded ends
readonly property int barHeight:       40  // must match Bar.qml barHeight
readonly property int barTopGap:        6  // must match Bar.qml topGap
readonly property int belowBarGap:      8  // gap between bar bottom and island top
```

`margins.top = barHeight + barTopGap + belowBarGap`

### State machine
```
idle → pill-in → expanding → visible → contracting → pill-out → idle
```

| State | What happens |
|-------|-------------|
| `idle` | `Loader.active = false`, pill at scale 0, no hit testing |
| `pill-in` | `Loader.active = true`; pill `scale` animates 0 → 1 with `Easing.OutBack`. Expansion begins only once `Loader.status === Loader.Ready`. |
| `expanding` | Pill `width`/`height` animate to `loader.item.implicitWidth + padding*2` / `loader.item.implicitHeight + padding*2` with `Easing.OutCubic` |
| `visible` | Content opacity animates to 1; timeout running; `+N` badge visible (z-ordered above content, right-aligned; safe because notification content is left-aligned) if `pendingCount > 0` |
| `contracting` | Content opacity → 0; pill `width`/`height` → pillWidth/pillHeight with `Easing.InCubic` |
| `pill-out` | Pill `scale` → 0 with `Easing.InBack`; on complete: service pops activity |

Transitions are driven by a simple `state` string property reacting to `DynamicIslandService.currentActivity`.

### Rendering
```qml
Rectangle {
    id: pill
    // width/height animated by state machine
    radius: pillRadius
    color: Theme.surface_container  // or urgency override from data
    border …

    Loader {
        id: contentLoader
        anchors.fill: parent
        anchors.margins: islandPadding
        sourceComponent: DynamicIslandService.currentActivity?.contentComponent ?? null
        // pass data through
        onLoaded: item.data = DynamicIslandService.currentActivity.data
    }

    // +N badge — only visible when pendingCount > 0
    Text {
        visible: DynamicIslandService.pendingCount > 0
        text: "+" + DynamicIslandService.pendingCount
        anchors { right: parent.right; rightMargin: islandPadding; verticalCenter: parent.verticalCenter }
        …
    }
}
```

---

## `NotificationActivity.qml`

**Type:** `Item` (activity content widget)

**Expected `data` fields:** `{ appName: string, summary: string, urgency: int }`

### Layout
```
[ app icon (28×28, rounded) ]  [ column: APP NAME (9px caps) / Summary (12px bold) ]
```

### Sizing
- `implicitWidth`: fixed at `320` (fits most notification text; summary elides if longer)
- `implicitHeight`: `28` (icon height) — single fixed height for notifications; no body text shown in island

### Urgency styling
- `urgency === 2`: pill border color overridden to `Theme.error` via `data.urgency` read in `DynamicIsland.qml`
- Normal: `Theme.outline_variant` border

---

## `shell.qml` changes

### Remove
```qml
NotificationPopups { id: notifPopups; notifServer: notifServer }
```

### Add
```qml
DynamicIsland {}   // in modules/island
```

### Update notification handler
```js
// NotificationServer.onNotification
notif.tracked = true;
if (notif.lastGeneration) return;

const id = DynamicIslandService.push({
    contentComponent: Qt.createComponent("modules/island/NotificationActivity.qml"),
    priority: 10,
    durationMs: notif.expireTimeout > 0
        ? Math.min(Math.round(notif.expireTimeout * 1000), 5000)
        : 5000,
    data: {
        appName:  notif.appName  || "",
        summary:  notif.summary  || "",
        urgency:  notif.urgency
    }
});
notif.closed.connect(() => DynamicIslandService.remove(id));
```

`NotificationPopups.qml` is deleted from the repo.

---

## What's explicitly out of scope

- Changes to `NotifPanel.qml` — the notification panel is untouched
- App icon fetching — the icon placeholder uses a nerd font glyph; real icon lookup is a future widget enhancement
- Interaction/click on the island — no action on tap for v1; can be added per-activity later
- Multi-monitor: island appears on the primary/focused screen only (same as current popups)
