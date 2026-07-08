# Dynamic Island v2 — Design Spec

**Date:** 2026-07-08  
**Status:** Approved for implementation planning  
**Scope:** Full rethink of Quickshell Dynamic Island — behavior, visuals, activity system, workspace overlap, OSD merge

---

## 1. Goals

Replace the current notification-only island with an iOS Dynamic Island–inspired system that:

- Lives at **top-center**, pulled out by hovering an **invisible edge activation strip** (dock-style)
- Supports **multiple activity types** with priority-based queueing
- Uses **solid black** morphing chrome (compact ↔ expanded)
- **Overlays** workspace indicators when active (no bar layout changes)
- Merges **volume/brightness/night-light feedback** into the island as **non-interactive bursts** (no sliders)
- Keeps **transport controls hidden** until the mouse hovers the expanded island

### Non-goals (v1)

- Cloud Center UI for hover-zone settings (QML tunables only)
- Draggable OSD sliders
- Manual activity pinning
- Keyboard-driven expand (hover is primary)
- Relocating workspace icons in the bar

---

## 2. Current State

| File | Role |
|------|------|
| `modules/island/DynamicIsland.qml` | PanelWindow shell, pill morph animation, per-screen `Variants` |
| `modules/island/DynamicIslandService.qml` | Activity queue, priorities, screenshot/recording/notif |
| `modules/island/NotificationActivity.qml` | Notification compact content |
| `modules/island/ScreenshotActivity.qml` | Screenshot preview + actions |
| `modules/island/RecordingActivity.qml` | Recording preview + actions |
| `modules/island/RecordPickerActivity.qml` | Recording mode picker |
| `modules/sliders/Sliders.qml` | Separate OSD overlay with draggable sliders |
| `Bar.qml` (center row) | Workspace indicators at top-center |
| `Theme.qml` | `island*` layout constants (must live in matugen template too) |

**Known pain points addressed by v2:**

- Island spawned below workspaces (`islandTopMargin`) — awkward stacking
- OSD and island are separate systems with duplicated chrome
- No persistent live activities (media, timers)
- No hover-to-expand interaction model
- Matugen can wipe `Theme.qml` island constants if not in template

---

## 3. Architecture

### 3.1 Three layers

```
┌─────────────────────────────────────────────────────────┐
│  IslandShell.qml                                        │
│  - Always-present per-screen PanelWindow (Variants)     │
│  - Invisible top-edge activation strip (dock pattern)   │
│  - Shell states: collapsed | peek | compact | expanded  │
│  - Morph animations (width/height/radius)               │
│  - Hover detection: edge → peek/compact; body → expand  │
│  - WlrLayer.Overlay (above bar / workspaces)            │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  IslandService.qml (extends DynamicIslandService)       │
│  - Activity queue with tiers: persistent / transient    │
│  - Priority-based interrupt + resume                    │
│  - Timers, MPRIS hooks, OSD event intake                │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Activity plugins (QML components)                      │
│  Each provides: compactView, expandedView, metadata     │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Activity plugin contract

Each activity type registers:

| Field | Type | Description |
|-------|------|-------------|
| `activityType` | string | Unique id (`media`, `osd`, `notification`, …) |
| `tier` | enum | `persistent` \| `transient` |
| `priority` | int | Higher preempts lower |
| `durationMs` | int | `0` = no auto-dismiss (persistent) |
| `compactComponent` | Component | Shown in compact state |
| `expandedComponent` | Component | Shown when island body hovered |
| `data` | object | Activity-specific payload |

Shell calls `_applyActivityToLoader()` pattern (existing) but with separate compact/expanded loaders or a single loader that swaps mode.

### 3.3 File plan

| Action | Path |
|--------|------|
| **Add** | `modules/island/IslandShell.qml` — replaces `DynamicIsland.qml` |
| **Rename/extend** | `DynamicIslandService.qml` → `IslandService.qml` (keep alias in qmldir during migration) |
| **Add** | `modules/island/activities/MediaActivity.qml` |
| **Add** | `modules/island/activities/OsdBurstActivity.qml` |
| **Add** | `modules/island/activities/TimerActivity.qml` |
| **Add** | `modules/island/activities/DownloadActivity.qml` |
| **Add** | `modules/island/activities/SystemBurstActivity.qml` |
| **Refactor** | `NotificationActivity.qml` — compact + expanded views |
| **Keep/refactor** | `ScreenshotActivity.qml`, `RecordingActivity.qml`, `RecordPickerActivity.qml` |
| **Remove** | `modules/sliders/Sliders.qml` — logic absorbed into service |
| **Update** | `shell.qml` — wire MPRIS, timer, volume keys to `IslandService` |
| **Update** | `qmldir` |
| **Update** | `.config/matugen/templates/quickshell-theme.qml` — island constants |
| **Add** | `Theme.qml` island chrome tokens for black shell (see §5) |

---

## 4. Shell States & Interaction

### 4.1 State machine

```
collapsed ──(hover activation strip)──► peek | compact
peek/compact ──(hover island body)───► expanded
any active ──(mouse leave + delay)───► collapsed
```

| State | Visible UI | Window size |
|-------|------------|-------------|
| `collapsed` | Nothing (invisible edge strip only) | `activationHeight` × `activationWidth` |
| `peek` | Idle peek panel (recent activity, quick hints) | Content-driven, max `islandMaxWidth` |
| `compact` | Persistent activity pill (media, timer) or transient glance | Activity compact implicit size |
| `expanded` | Full activity layout + hover-revealed controls | Activity expanded implicit size |

### 4.2 Hover rules

1. **Activation strip** (top screen edge, invisible): always peekable — even when idle.
2. **Island body hover**: morph compact/peek → expanded.
3. **Controls** (media prev/play/next): `visible` only when `islandBodyHovered`.
4. **Leave delay**: `peekHideDelayMs` (default 500ms, matches dock) before collapsing.

### 4.3 QML tunables (IslandShell)

```qml
readonly property int activationHeight: 1    // invisible edge strip (dock parity)
readonly property int activationWidth: 360   // centered hit area
readonly property int peekHideDelayMs: 500
readonly property int shellRadiusCompact: 28
readonly property int shellRadiusExpanded: 32
```

No `islandTopMargin` offset — shell aligns vertically with **bar center row**, not below it.

### 4.4 Workspace overlap (overlay model)

- **Bar layout unchanged** — workspace icons stay in center row.
- Island uses `WlrLayer.Overlay` above the bar.
- When island is `peek`, `compact`, or `expanded`, it **draws over** workspace icons.
- When `collapsed`, workspaces are fully visible and clickable.
- Island grows **downward** from the bar-center band; does not stack below workspaces.

```
Screen top
├─ invisible activation strip (y=0, height=activationHeight)
├─ Bar (transparent) — workspaces at horizontal center
└─ Island overlay (when active) — covers workspaces, expands down
```

---

## 5. Visual Language

### 5.1 Chrome

- **Solid black** shell: `Qt.rgba(0, 0, 0, 0.95)` (not `Theme.glassShell`)
- **Border:** subtle `rgba(255,255,255,0.12)` rim optional
- **Radius:** morphs between compact (28px) and expanded (32px)
- **Typography:** JetBrainsMono Nerd Font for system text; media title/artist hierarchy per approved mockup
- **Blur:** Hyprland layer blur rule remains (`quickshell:island`); black shell is mostly opaque — blur is subtle

### 5.2 Approved mockup states

| State | Description |
|-------|-------------|
| **Idle peek** | Recent notification line + quick hints (volume/brightness/timers) |
| **Compact media** | Album art + truncated title + waveform bars; **no transport controls** |
| **Expanded media** | Full title/artist, progress bar, timestamps; transport + output icon on **body hover only** |

Reference: `.superpowers/brainstorm/.../island-states-v1.html`

### 5.3 Theme tokens

Add to `quickshell-theme.qml` (and generated `Theme.qml`):

```qml
// Island layout (existing)
readonly property int islandMaxWidth: 360
readonly property int islandMaxHeight: 220
// ... existing islandShell* constants ...

// Island v2 chrome
readonly property color islandShellFill: Qt.rgba(0, 0, 0, 0.95)
readonly property color islandShellBorder: Qt.rgba(1, 1, 1, 0.12)
readonly property color islandTextPrimary: Qt.rgba(1, 1, 1, 0.95)
readonly property color islandTextSecondary: Qt.rgba(1, 1, 1, 0.55)
```

---

## 6. Activity Types

### 6.1 Priority table

| Activity | Tier | Priority | Duration | Interrupts |
|----------|------|----------|----------|------------|
| OSD burst | transient | 90 | 2000ms | notifications |
| Screenshot / recording | transient | 25 | existing | notifications |
| System burst | transient | 20 | 3000ms | notifications |
| Download progress | transient | 15 | until complete | notifications |
| Notification | transient | 10 | 5000ms (max) | — |
| Media | persistent | — | while playing | — |
| Timer | persistent | — | while running | — |

### 6.2 OSD burst (replaces Sliders.qml)

- **Trigger:** existing volume/brightness/night-light key bindings (via `IpcHandler` / hyprland binds)
- **Display:** icon + percentage (or `Muted` / `3500K`) — **no slider widget**
- **Behavior:** push transient activity, auto-dismiss 2s, interrupt notifications
- **Implementation:** absorb `Sliders.qml` state readers (`wpctl`, `brightnessctl`, nightlight script) into `IslandService`

### 6.3 Media (MPRIS)

- **Source:** `Quickshell.Services.Mpris` (already imported in `Bar.qml`)
- **Persistent** while playback active
- **Compact:** art + title + waveform
- **Expanded:** full player UI per mockup; controls on body hover
- **Priority:** resuming/starting playback interrupts notifications

### 6.4 Timer

- **Source:** `TimerService` (existing module)
- **Persistent** while timer running
- **Compact:** icon + remaining time
- **Expanded:** label, pause/reset actions (if applicable)

### 6.5 Notification

- Redesigned compact: app icon + app name + summary (existing data)
- Expanded: optional longer body text
- Urgency 2 (critical): red-tinted shell border (keep existing urgency handling)

### 6.6 Screenshot / recording

- Keep existing rich previews and actions (copy, dismiss, drag)
- Default to **expanded** state (not compact pill)
- Priority 25 — interrupts notifications, not media persistent slot

### 6.7 Download / system bursts

- **Download:** progress percentage + filename (hook TBD — file copy events or user script IPC)
- **System:** battery low, wifi connect, etc. (hook TBD — start with manual `IslandService.push` IPC for testing)

---

## 7. Queue & Interrupt Logic

### 7.1 Rules

1. **Transient interrupts transient** if incoming `priority` > current.
2. **Transient interrupts persistent display** temporarily; on dismiss, **restore persistent** activity.
3. **Persistent activities** (media, timer) hold the compact slot when no transient is active.
4. **Multiple persistent:** highest priority wins (media > timer); or most recent — **media wins** if both active.
5. **`pendingCount` badge:** show `+N` on compact state when queue has waiting transients (polish existing badge).

### 7.2 Idle peek content

When nothing persistent is active and user hovers activation strip:

- Last transient activity summary (if recent, within ~30s cache), OR
- Minimal empty state: "No active items" + quick hints

---

## 8. Multi-monitor

- `IslandShell` uses `Variants { model: Quickshell.screens }` (existing pattern)
- Each screen gets independent shell + activation strip
- Activity service is **singleton** — show on focused monitor only OR all monitors

**Decision:** show on **focused monitor only** (match dock/bar focus behavior) — service sets `targetScreen` on push; shell on other screens stays collapsed.

---

## 9. Migration & Compatibility

### 9.1 shell.qml changes

- Replace `QuickIsland.DynamicIsland {}` → `QuickIsland.IslandShell {}`
- Remove `QuickSliders.Sliders {}`
- Wire `sliderController` references in `NotifPanel.qml` to `IslandService` OSD methods
- Keep existing IPC targets (`sliders.showVolume`, etc.) as thin wrappers on `IslandService`

### 9.2 Hyprland layer rules

Keep existing `quickshell:island` blur rule in `windowrules.lua`. Namespace unchanged to avoid config churn.

### 9.3 Breaking changes

- `modules/sliders/` removed — any external `qs ipc call sliders` still works via compatibility shims in `IslandService`
- Visual position changes — island no longer at `islandTopMargin` below bar

---

## 10. Testing Checklist

Manual verification on single + multi-monitor:

- [ ] Invisible top-edge hover pulls out idle peek
- [ ] Workspaces clickable when island collapsed; covered when island active
- [ ] Volume key shows OSD burst (icon + %), no slider, auto-dismiss
- [ ] Brightness / night-light bursts work
- [ ] Notification compact glance; interrupted by volume
- [ ] Media compact pill while playing; expand on body hover; controls only on hover
- [ ] Timer compact while running
- [ ] Screenshot preview with actions
- [ ] Recording picker + preview
- [ ] `+N` badge when notifications queue
- [ ] Theme regen (matugen) preserves island constants
- [ ] Reload quickshell — no `Unable to assign [undefined]` errors

---

## 11. Implementation Order (high level)

1. Theme tokens + matugen template
2. `IslandShell` scaffold (states, activation strip, morph shell)
3. `IslandService` queue refactor (tiers, interrupt/resume)
4. `OsdBurstActivity` + remove `Sliders.qml`
5. Refactor `NotificationActivity` (compact/expanded)
6. `MediaActivity` + MPRIS wiring
7. `TimerActivity` wiring
8. Migrate screenshot/recording activities to new shell
9. Idle peek content
10. Download/system burst stubs + IPC
11. Multi-monitor focus routing
12. Polish animations + `peekHideDelayMs` tuning

---

## 12. Open Items (post-v1)

- Download progress event source
- System burst triggers (battery, network)
- Cloud Center settings page for `activationHeight` / `activationWidth`
- Keyboard shortcut to toggle island expand

---

## Approval

Design approved in brainstorming session 2026-07-08:

- Full rethink, iOS Dynamic Island aesthetic (solid black)
- Activity plugin architecture
- Invisible dock-style top activation strip
- Overlay workspace model
- OSD as non-interactive burst (no sliders)
- Media/timer persistent; hover-expand with controls on body hover only
