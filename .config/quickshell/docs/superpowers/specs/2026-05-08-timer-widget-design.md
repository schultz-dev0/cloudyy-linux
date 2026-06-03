# Timer Widget Design

**Date:** 2026-05-08  
**Status:** Approved  

## Overview

A Quickshell timer widget for contractor time tracking. Supports multiple simultaneous stopwatch and countdown timers with project labels. Accessible from the bar and via a keybinding. Sessions are logged to monthly markdown files.

---

## Bar Module

A pill component placed immediately right of the Spotlight module in the left bar row. Implemented as `TimerBarPill.qml`.

**States:**

| State | Appearance |
|---|---|
| Idle (no timers) | `⏱ Timer` in muted text |
| 1 running | `▶ 01:24:37` in accent purple, live ticking |
| Multiple running | `▶ 01:24:37 +2` — most-recent timer + badge count of others running |
| Countdown warning (any countdown < 5 min remaining) | Time and play icon turn red, `⚠` badge appears |

Click anywhere on the pill to open/close the timer panel.

---

## Timer Panel

A `PanelWindow` anchored `bottom: true; left: true`, consistent with the calculator panel pattern. Width ~340px. Opens/closes via `root.timerOpen` state in `shell.qml` with scale + opacity animation (`transformOrigin: Item.BottomLeft`).

### Layout

```
┌─────────────────────────────────────┐
│  Timers                      [+ New]│
├─────────────────────────────────────┤
│ ▌ ▶ RUNNING · STOPWATCH             │
│   Gemini 3.1 ambiguous prompt...  ✏ ✕│
│   01:24:37                   [⏸][■] │
├─────────────────────────────────────┤
│ ▌ ⏸ PAUSED · COUNTDOWN 2:00:00     │
│   Client review — API docs        ✏ ✕│
│   00:35:48                   [▶][■] │
│   ████░░░░░░░░░░░░░░░░░░░░░░░░░ 30% │
├─────────────────────────────────────┤
│  HISTORY                  12 entries│
│  Gemini 3.1 prompt training  2h 10m │
│  Client review — API docs      45m  │
│  Codebase refactor sprint    3h 05m │
└─────────────────────────────────────┘
```

### Timer Cards

Each active timer renders as `TimerCard.qml`. Card properties:

- **Purple left border** — running
- **Amber left border** — paused
- **Status line** — `▶ RUNNING · STOPWATCH` or `⏸ PAUSED · COUNTDOWN 2:00:00`
- **Label** — project name, truncated with ellipsis, full text on hover
- **Time display** — 22px bold monospace; turns red when countdown < 5 min
- **Controls** — pause/resume toggle + stop (■); stop button saves to history
- **Progress bar** — countdown only; drains left-to-right, turns red under 5 min
- **Edit (✏)** — inline rename of label
- **Dismiss (✕)** — removes card without saving to history (confirms before discarding if time > 0)

### New Timer Form

Triggered by `[+ New]` button. The form slides in inline at the top of the panel (card list shifts down), implemented in `NewTimerForm.qml`.

Fields:
1. **Project / Label** — text input, auto-focused on open
2. **Mode toggle** — `Stopwatch` | `Countdown` (segmented button)
3. **Duration picker** — hours + minutes spinboxes; only enabled in Countdown mode
4. **[▶ Start Timer]** — creates the timer and returns to card view

Pressing `Escape` or `✕ Cancel` dismisses the form.

### History Section

Always visible at the bottom of the panel (below active timers), scrollable. Shows the 10 most recent completed sessions. Each row: `label` (truncated) + `duration · relative date`. Full history is in the markdown files; the panel reads the current month's file via a `Process` call on open.

An `export` link beside the history header opens the current month's file in the default text editor (`xdg-open`).

---

## Data Storage

Completed sessions are appended to `~/Desktop/timer_record/YYYY-MM.md` — one file per calendar month.

**Format:**

```markdown
## 2026-05-08

| Started | Project | Duration | Mode |
|---------|---------|----------|------|
| 14:32 | Gemini 3.1 ambiguous prompt handling | 1h 24m | stopwatch |
| 09:15 | Client review — API docs | 45m | countdown (2h) |
```

Write is performed by a shell script `modules/timer/timer_log.sh` invoked via Quickshell's `Process` component when a timer is stopped. Arguments: `label`, `duration_seconds`, `mode`, `target_seconds` (countdown only).

The script:
- Creates `~/Desktop/timer_record/` if it doesn't exist
- Creates or appends to `YYYY-MM.md`
- Inserts a `## YYYY-MM-DD` heading if needed (first entry of the day)
- Appends a table row

---

## Architecture

### Module Structure

```
modules/timer/
├── qmldir
├── TimerPanel.qml       # PanelWindow, anchors bottom+left
├── TimerCard.qml        # Single timer card component
├── NewTimerForm.qml     # Inline new timer creation form
├── TimerBarPill.qml     # Bar pill widget
└── timer_log.sh         # Appends completed sessions to markdown
```

### State (shell.qml)

```qml
property bool timerOpen: false

ListModel {
    id: timers
    // roles: timerId, label, mode, targetSeconds, elapsedSeconds, timerState
}
```

`TimerPanel` and `TimerBarPill` both read `root.timerOpen` and `root.timers`. The `ListModel` roles are: `timerId` (string), `label` (string), `mode` (`"stopwatch"` | `"countdown"`), `targetSeconds` (int, countdown only), `elapsedSeconds` (int), `timerState` (`"running"` | `"paused"`).

Each running timer card owns a Qt `Timer { interval: 1000 }` element that increments `elapsedSeconds` and checks countdown completion.

### IPC + Keybinding

```qml
// shell.qml
IpcHandler {
    target: "timer"
    function toggle() { root.timerOpen = !root.timerOpen }
}
```

Hyprland config:
```
bind = $mainMod SHIFT, T, exec, qs ipc call timer toggle
```

Close on `Escape` is handled inside `TimerPanel.qml` via a `Keys.onEscapePressed` handler.

---

## Out of Scope

- Export to CSV or invoice format (viewing markdown files is sufficient)
- Cloud sync or cross-device history
- Timer templates / presets
- Notifications on countdown completion (can be added later)
