# Timer Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-timer bar widget + bottom-left panel supporting stopwatch/countdown modes, project labels, pause/resume, and monthly markdown session logs.

**Architecture:** A `TimerService` Quickshell singleton owns all runtime state (ListModel, tick Timer, add/pause/resume/stop/dismiss functions, log Process). `TimerPanel` and `TimerBarPill` are separate QML components that read from the singleton directly — no prop-drilling. `shell.qml` instantiates `TimerPanel` and registers the IPC handler; `Bar.qml` hosts `TimerBarPill` right of the Spotlight field.

**Tech Stack:** QML/Qt Quick (Quickshell), Bash (`timer_log.sh` for markdown persistence)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `modules/timer/qmldir` | Create | Module declaration |
| `modules/timer/TimerService.qml` | Create | Singleton: state, tick, add/pause/resume/stop/dismiss/rename, log writer |
| `modules/timer/TimerPanel.qml` | Create | PanelWindow: card list, new-timer form host, history section |
| `modules/timer/TimerCard.qml` | Create | Single timer card with controls, edit, dismiss-confirm |
| `modules/timer/NewTimerForm.qml` | Create | Inline form: label, mode toggle, duration → start |
| `modules/timer/TimerBarPill.qml` | Create | Bar pill: 4 states, click to toggle panel |
| `modules/timer/timer_log.sh` | Create | Append completed session to `~/Desktop/timer_record/YYYY-MM.md` |
| `shell.qml` | Modify | Add import, IpcHandler target "timer", `QuickTimer.TimerPanel {}` |
| `Bar.qml` | Modify | Add import, insert `QuickTimer.TimerBarPill {}` after spotlight field |
| `.config/hypr/source/bindings.conf` | Modify | Add `$mainMod SHIFT, T` keybinding |

---

## Task 1: Module scaffold — stubs + full wiring

Gets the module importable and the panel toggling before any UI work. Verifies the entire wiring chain (IPC → TimerService.open → panel visible) with stub components.

**Files:**
- Create: `modules/timer/qmldir`
- Create: `modules/timer/TimerService.qml` (stub)
- Create: `modules/timer/TimerPanel.qml` (stub)
- Create: `modules/timer/TimerBarPill.qml` (stub)
- Create: `modules/timer/TimerCard.qml` (stub)
- Create: `modules/timer/NewTimerForm.qml` (stub)
- Modify: `shell.qml`
- Modify: `Bar.qml`
- Modify: `.config/hypr/source/bindings.conf`

- [ ] **Step 1: Create qmldir**

File: `modules/timer/qmldir`
```
module QuickTimer
singleton TimerService 1.0 TimerService.qml
TimerPanel 1.0 TimerPanel.qml
TimerCard 1.0 TimerCard.qml
NewTimerForm 1.0 NewTimerForm.qml
TimerBarPill 1.0 TimerBarPill.qml
```

- [ ] **Step 2: Create stub TimerService.qml**

File: `modules/timer/TimerService.qml`
```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false
    readonly property ListModel timers: ListModel {}
    property string homeDir: ""

    readonly property Process _homeReader: Process {
        command: ["sh", "-c", "echo $HOME"]
        running: true
        stdout: SplitParser {
            onRead: line => root.homeDir = line.trim()
        }
    }
}
```

- [ ] **Step 3: Create stub TimerPanel.qml**

File: `modules/timer/TimerPanel.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: timerWindow

    readonly property int panelWidth:  340
    readonly property int panelRadius: 20
    readonly property int padding:     16

    anchors { bottom: true; left: true }
    margins { bottom: 16; left: 16 }
    implicitWidth:  panelWidth
    implicitHeight: panelRect.implicitHeight
    color:          "transparent"
    visible:        TimerService.open

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:timer"
    WlrLayershell.keyboardFocus: TimerService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Keys.onEscapePressed: TimerService.open = false

    Rectangle {
        id: panelRect
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        implicitHeight: 120
        radius: timerWindow.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        opacity: TimerService.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        scale: TimerService.open ? 1.0 : 0.88
        transformOrigin: Item.BottomLeft
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        Text {
            anchors.centerIn: parent
            text: "⏱ Timer panel (stub)"
            color: Theme.on_surface
            font.pixelSize: 13
        }
    }
}
```

- [ ] **Step 4: Create stub TimerBarPill.qml**

File: `modules/timer/TimerBarPill.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Rectangle {
    implicitWidth: 80; implicitHeight: 28
    radius: 14
    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)

    Text {
        anchors.centerIn: parent
        text: "⏱ Timer"
        color: Theme.on_surface_variant
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: TimerService.open = !TimerService.open
    }
}
```

- [ ] **Step 5: Create stub TimerCard.qml and NewTimerForm.qml**

File: `modules/timer/TimerCard.qml`
```qml
import QtQuick
Rectangle {
    required property string timerId
    required property string label
    required property string mode
    required property int    targetSeconds
    required property int    elapsedSeconds
    required property string timerState
    implicitWidth: 200; implicitHeight: 40
    color: "transparent"
}
```

File: `modules/timer/NewTimerForm.qml`
```qml
import QtQuick
Rectangle {
    signal startTimer(string label, string mode, int targetSeconds)
    signal cancel()
    implicitWidth: 200; implicitHeight: 40
    color: "transparent"
}
```

- [ ] **Step 6: Wire shell.qml — import + IpcHandler + TimerPanel**

In `shell.qml`, make three edits:

**After line 12** (after `import "modules/calculator" as QuickCalculator`), add:
```qml
import "modules/timer" as QuickTimer
```

**After the calculator IpcHandler closing `}` (after line 90)**, add:
```qml
    IpcHandler {
        target: "timer"
        function toggle() { QuickTimer.TimerService.open = !QuickTimer.TimerService.open }
        function show()   { QuickTimer.TimerService.open = true }
        function hide()   { QuickTimer.TimerService.open = false }
    }
```

**After `QuickSpotlight.Spotlight {}` (line 138)**, add:
```qml
    QuickTimer.TimerPanel {}
```

- [ ] **Step 7: Wire Bar.qml — import + pill insertion**

At the top of `Bar.qml` imports section, add:
```qml
import "modules/timer" as QuickTimer
```

Find the closing `}` of the `spotlightField` Rectangle (around line 417). Immediately after it, still inside the left row, add:
```qml
                QuickTimer.TimerBarPill {}
```

- [ ] **Step 8: Add keybinding**

In `.config/hypr/source/bindings.conf`, after the calculator binding line, add:
```
bindd = $mainMod SHIFT, T, Open timer panel, exec, quickshell ipc call timer toggle
```

- [ ] **Step 9: Verify scaffold loads**

Reload Quickshell (kill and restart, or use your configured reload binding).

Expected:
- `⏱ Timer` pill appears right of the Spotlight field in the bar
- `$mainMod SHIFT T` toggles the stub panel (animates in bottom-left)
- `Escape` closes it
- No QML errors in `journalctl --user -u quickshell -f`

- [ ] **Step 10: Commit**

```bash
git add modules/timer/ shell.qml Bar.qml .config/hypr/source/bindings.conf
git commit -m "feat: scaffold timer module with stubs + full shell/bar/keybinding wiring"
```

---

## Task 2: timer_log.sh — markdown persistence

Write and test the log script in isolation before QML wires it up.

**Files:**
- Create: `modules/timer/timer_log.sh`

- [ ] **Step 1: Create the script**

File: `modules/timer/timer_log.sh`
```bash
#!/usr/bin/env bash
# Usage: timer_log.sh <label> <elapsed_seconds> <mode> [target_seconds]
set -euo pipefail

LABEL="$1"
ELAPSED_SECONDS="$2"
MODE="$3"
TARGET_SECONDS="${4:-0}"

RECORD_DIR="$HOME/Desktop/timer_record"
mkdir -p "$RECORD_DIR"

format_duration() {
    local secs=$1
    local h=$((secs / 3600))
    local m=$(( (secs % 3600) / 60 ))
    local s=$((secs % 60))
    if [ "$h" -gt 0 ]; then
        printf "%dh %02dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf "%dm %02ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

MONTH_FILE="$RECORD_DIR/$(date '+%Y-%m').md"
TODAY="$(date '+%Y-%m-%d')"
START_TIME="$(date '+%H:%M')"
DURATION="$(format_duration "$ELAPSED_SECONDS")"

if [ "$MODE" = "countdown" ] && [ "$TARGET_SECONDS" -gt 0 ]; then
    TARGET="$(format_duration "$TARGET_SECONDS")"
    MODE_LABEL="countdown ($TARGET)"
else
    MODE_LABEL="stopwatch"
fi

if [ ! -f "$MONTH_FILE" ]; then
    printf "# Timer Log — %s\n\n" "$(date '+%B %Y')" > "$MONTH_FILE"
fi

if ! grep -qF "## $TODAY" "$MONTH_FILE" 2>/dev/null; then
    printf "\n## %s\n\n| Started | Project | Duration | Mode |\n|---------|---------|----------|------|\n" \
        "$TODAY" >> "$MONTH_FILE"
fi

printf "| %s | %s | %s | %s |\n" "$START_TIME" "$LABEL" "$DURATION" "$MODE_LABEL" >> "$MONTH_FILE"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x modules/timer/timer_log.sh
```

- [ ] **Step 3: Test stopwatch entry**

```bash
bash modules/timer/timer_log.sh "Test project alpha" 3725 "stopwatch"
cat ~/Desktop/timer_record/$(date '+%Y-%m').md
```

Expected output in the file:
```
# Timer Log — May 2026

## 2026-05-08

| Started | Project | Duration | Mode |
|---------|---------|----------|------|
| HH:MM | Test project alpha | 1h 02m | stopwatch |
```

- [ ] **Step 4: Test countdown entry**

```bash
bash modules/timer/timer_log.sh "Client review" 2700 "countdown" 7200
cat ~/Desktop/timer_record/$(date '+%Y-%m').md
```

Expected: row appended with mode `countdown (2h 00m)`

- [ ] **Step 5: Commit**

```bash
git add modules/timer/timer_log.sh
git commit -m "feat: add timer_log.sh for monthly markdown session logging"
```

---

## Task 3: TimerService — full singleton

Replaces the stub with state management: ListModel, per-second ticker, add/pause/resume/stop/dismiss/rename, and Process-based log writer.

**Files:**
- Modify: `modules/timer/TimerService.qml`

- [ ] **Step 1: Replace TimerService.qml with full implementation**

File: `modules/timer/TimerService.qml`
```qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── Public state ──────────────────────────────────────────────────────
    property bool open: false
    readonly property ListModel timers: ListModel {}
    property string homeDir: ""

    // ── Computed properties for TimerBarPill ──────────────────────────────
    readonly property int runningCount: {
        let n = 0
        for (let i = 0; i < timers.count; i++)
            if (timers.get(i).timerState === "running") n++
        return n
    }

    readonly property var primaryTimer: {
        for (let i = timers.count - 1; i >= 0; i--) {
            const t = timers.get(i)
            if (t.timerState === "running") return t
        }
        return null
    }

    readonly property bool hasCountdownWarning: {
        for (let i = 0; i < timers.count; i++) {
            const t = timers.get(i)
            if (t.mode === "countdown" && t.timerState === "running") {
                const remaining = t.targetSeconds - t.elapsedSeconds
                if (remaining > 0 && remaining < 300) return true
            }
        }
        return false
    }

    // ── $HOME reader ─────────────────────────────────────────────────────
    readonly property Process _homeReader: Process {
        command: ["sh", "-c", "echo $HOME"]
        running: true
        stdout: SplitParser {
            onRead: line => root.homeDir = line.trim()
        }
    }

    // ── Per-second tick ───────────────────────────────────────────────────
    readonly property Timer ticker: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            for (let i = 0; i < root.timers.count; i++) {
                const t = root.timers.get(i)
                if (t.timerState !== "running") continue
                const next = t.elapsedSeconds + 1
                root.timers.setProperty(i, "elapsedSeconds", next)
                if (t.mode === "countdown" && next >= t.targetSeconds) {
                    root._finishTimer(i)
                    i--
                }
            }
        }
    }

    // ── Log writer ────────────────────────────────────────────────────────
    readonly property string _scriptPath: Qt.resolvedUrl("timer_log.sh").toString().slice(7)
    readonly property Component _logProto: Component { Process {} }

    function _writeLog(label, elapsedSeconds, mode, targetSeconds) {
        const p = _logProto.createObject(root, {
            command: ["bash", root._scriptPath, label,
                      String(elapsedSeconds), mode, String(targetSeconds)]
        })
        p.runningChanged.connect(() => { if (!p.running) p.destroy() })
        p.running = true
    }

    // ── Internal helpers ──────────────────────────────────────────────────
    function _findTimer(timerId) {
        for (let i = 0; i < timers.count; i++)
            if (timers.get(i).timerId === timerId) return i
        return -1
    }

    function _finishTimer(idx) {
        const t = timers.get(idx)
        _writeLog(t.label, t.elapsedSeconds, t.mode, t.targetSeconds)
        timers.remove(idx)
    }

    // ── Public API ────────────────────────────────────────────────────────
    function addTimer(label, mode, targetSeconds) {
        timers.append({
            timerId:        String(Date.now()),
            label:          label,
            mode:           mode,
            targetSeconds:  targetSeconds || 0,
            elapsedSeconds: 0,
            timerState:     "running"
        })
    }

    function pauseTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) timers.setProperty(idx, "timerState", "paused")
    }

    function resumeTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) timers.setProperty(idx, "timerState", "running")
    }

    function stopTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) _finishTimer(idx)
    }

    function dismissTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) timers.remove(idx)
    }

    function renameTimer(timerId, newLabel) {
        const idx = _findTimer(timerId)
        if (idx >= 0) timers.setProperty(idx, "label", newLabel)
    }
}
```

- [ ] **Step 2: Reload and verify no errors**

Reload Quickshell. Check logs:
```bash
journalctl --user -u quickshell -n 50
```
Expected: no QML errors. Panel still toggles with `$mainMod SHIFT T`.

- [ ] **Step 3: Commit**

```bash
git add modules/timer/TimerService.qml
git commit -m "feat: implement TimerService singleton with tick, state management, and log writer"
```

---

## Task 4: TimerBarPill — bar widget with 4 states

**Files:**
- Modify: `modules/timer/TimerBarPill.qml`

- [ ] **Step 1: Replace TimerBarPill.qml with full implementation**

File: `modules/timer/TimerBarPill.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Rectangle {
    id: pill

    readonly property var   pt:      TimerService.primaryTimer
    readonly property bool  warning: TimerService.hasCountdownWarning
    readonly property int   count:   TimerService.runningCount

    implicitWidth:  contentRow.implicitWidth + 16
    implicitHeight: 28
    radius:         14
    color:          Qt.rgba(Theme.surface_container.r,
                            Theme.surface_container.g,
                            Theme.surface_container.b, 0.8)

    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 5

        // Play/idle icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text:  pill.pt ? "▶" : "⏱"
            color: {
                if (!pill.pt)      return Theme.on_surface_variant
                if (pill.warning)  return Theme.error
                return Theme.primary
            }
            font.pixelSize: 11
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // Live time display
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !!pill.pt
            text: {
                if (!pill.pt) return ""
                if (pill.pt.mode === "countdown") {
                    const rem = Math.max(0, pill.pt.targetSeconds - pill.pt.elapsedSeconds)
                    return fmtTime(rem)
                }
                return fmtTime(pill.pt.elapsedSeconds)
            }
            color: pill.warning ? Theme.error : Theme.on_surface
            font.pixelSize: 12
            font.family:    "JetBrainsMono Nerd Font"
            font.weight:    Font.Bold
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        // "+N" badge for multiple running timers
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.count > 1
            width:  badgeText.implicitWidth + 8
            height: 16
            radius: 8
            color:  pill.warning
                    ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.8)
                    : Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.8)

            Text {
                id: badgeText
                anchors.centerIn: parent
                text:       "+" + (pill.count - 1)
                color:      pill.warning ? Theme.on_error_container : Theme.on_primary_container
                font.pixelSize: 9
                font.weight:    Font.Bold
            }
        }

        // "Timer" label shown only when idle
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !pill.pt
            text:  "Timer"
            color: Theme.on_surface_variant
            font.pixelSize: 12
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape:  Qt.PointingHandCursor
        onClicked:    TimerService.open = !TimerService.open
    }

    function fmtTime(secs) {
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        if (h > 0)
            return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
}
```

- [ ] **Step 2: Verify idle state**

Reload Quickshell. Confirm the pill shows `⏱ Timer` in muted color.

- [ ] **Step 3: Commit**

```bash
git add modules/timer/TimerBarPill.qml
git commit -m "feat: implement TimerBarPill with idle/running/multi/countdown-warning states"
```

---

## Task 5: TimerPanel — full panel shell

Builds the panel with animation, header, card list (using the stub TimerCard), and the new-timer form slot. History section is a placeholder — completed in Task 8.

**Files:**
- Modify: `modules/timer/TimerPanel.qml`

- [ ] **Step 1: Replace TimerPanel.qml with full implementation**

File: `modules/timer/TimerPanel.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: timerWindow

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property int panelWidth:  340
    readonly property int panelRadius: 20
    readonly property int padding:     16

    // ── History ───────────────────────────────────────────────────────────
    property var historyEntries: []
    readonly property string _historyFile:
        TimerService.homeDir + "/Desktop/timer_record/" + Qt.formatDate(new Date(), "yyyy-MM") + ".md"

    Process {
        id: historyReader
        command: ["bash", "-c", "cat '" + timerWindow._historyFile + "' 2>/dev/null"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("| ") || line.startsWith("| Started") || line.startsWith("|---")) return
                const parts = line.split("|").map(s => s.trim()).filter(s => s.length > 0)
                if (parts.length < 3) return
                timerWindow.historyEntries = timerWindow.historyEntries.concat([{
                    started:  parts[0],
                    label:    parts[1],
                    duration: parts[2],
                    mode:     parts[3] || ""
                }])
            }
        }
        onRunningChanged: {
            if (!running)
                timerWindow.historyEntries = timerWindow.historyEntries.slice().reverse()
        }
    }

    Process {
        id: fileOpener
        command: ["xdg-open", timerWindow._historyFile]
        running: false
    }

    // ── Local form state ──────────────────────────────────────────────────
    property bool showingNewForm: false

    // ── Window ────────────────────────────────────────────────────────────
    anchors { bottom: true; left: true }
    margins { bottom: 16; left: 16 }
    implicitWidth:  panelWidth
    implicitHeight: panelRect.implicitHeight
    color:          "transparent"
    visible:        TimerService.open

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:timer"
    WlrLayershell.keyboardFocus: TimerService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            timerWindow.historyEntries = []
            historyReader.running = true
        }
    }

    Keys.onEscapePressed: {
        if (showingNewForm) {
            showingNewForm = false
        } else {
            TimerService.open = false
        }
    }

    // ── Panel shell ───────────────────────────────────────────────────────
    Rectangle {
        id: panelRect
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        implicitHeight: contentCol.implicitHeight + timerWindow.padding * 2
        radius: timerWindow.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        opacity: TimerService.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        scale: TimerService.open ? 1.0 : 0.88
        transformOrigin: Item.BottomLeft
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        ColumnLayout {
            id: contentCol
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                margins: timerWindow.padding
            }
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "⏱  Timers"
                    color: Theme.on_surface
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: !timerWindow.showingNewForm
                    implicitWidth: newBtnLabel.implicitWidth + 16
                    implicitHeight: 24
                    radius: 12
                    color: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.8)

                    Text {
                        id: newBtnLabel
                        anchors.centerIn: parent
                        text: "+ New"
                        color: Theme.on_primary_container
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            timerWindow.showingNewForm = true
                        }
                    }
                }
            }

            // ── New timer form ─────────────────────────────────────────────
            NewTimerForm {
                Layout.fillWidth: true
                visible: timerWindow.showingNewForm
                onStartTimer: (label, mode, targetSecs) => {
                    TimerService.addTimer(label, mode, targetSecs)
                    timerWindow.showingNewForm = false
                }
                onCancel: timerWindow.showingNewForm = false
            }

            // ── Timer cards ───────────────────────────────────────────────
            Repeater {
                model: TimerService.timers
                delegate: TimerCard {
                    required property var model
                    Layout.fillWidth: true
                    timerId:        model.timerId
                    label:          model.label
                    mode:           model.mode
                    targetSeconds:  model.targetSeconds
                    elapsedSeconds: model.elapsedSeconds
                    timerState:     model.timerState
                }
            }

            // ── History divider ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                visible: timerWindow.historyEntries.length > 0
            }

            // ── History header ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: timerWindow.historyEntries.length > 0

                Text {
                    text: "HISTORY"
                    color: Theme.on_surface_variant
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }

                Text {
                    text: timerWindow.historyEntries.length + " entries · open file"
                    color: Theme.primary
                    font.pixelSize: 9
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fileOpener.running = true
                    }
                }
            }

            // ── History rows (up to 10 most recent) ───────────────────────
            Repeater {
                model: Math.min(timerWindow.historyEntries.length, 10)
                delegate: RowLayout {
                    required property int index
                    Layout.fillWidth: true

                    Text {
                        text: timerWindow.historyEntries[index].label
                        color: Theme.on_surface_variant
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: timerWindow.historyEntries[index].duration
                        color: Theme.on_surface_variant
                        font.pixelSize: 10
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify panel and history wiring**

Reload Quickshell. Press `$mainMod SHIFT T`:
- Panel animates in from bottom-left
- Header shows "⏱ Timers" + "+ New" button
- If `~/Desktop/timer_record/YYYY-MM.md` has entries from Task 2 testing, they appear under HISTORY
- Escape closes the new-form first (if open), then the panel

- [ ] **Step 3: Commit**

```bash
git add modules/timer/TimerPanel.qml
git commit -m "feat: implement TimerPanel with animations, card list, history section"
```

---

## Task 6: TimerCard — full card component

**Files:**
- Modify: `modules/timer/TimerCard.qml`

- [ ] **Step 1: Replace TimerCard.qml with full implementation**

File: `modules/timer/TimerCard.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: card

    // ── Input properties ──────────────────────────────────────────────────
    required property string timerId
    required property string label
    required property string mode
    required property int    targetSeconds
    required property int    elapsedSeconds
    required property string timerState

    // ── Local state ───────────────────────────────────────────────────────
    property bool editing:           false
    property bool confirmingDismiss: false

    // ── Computed ──────────────────────────────────────────────────────────
    readonly property bool   isCountdown: mode === "countdown"
    readonly property int    displaySecs: isCountdown
                                          ? Math.max(0, targetSeconds - elapsedSeconds)
                                          : elapsedSeconds
    readonly property bool   isWarning:   isCountdown && displaySecs < 300 && timerState === "running"
    readonly property double progress:    (isCountdown && targetSeconds > 0)
                                          ? Math.max(0, 1.0 - elapsedSeconds / targetSeconds)
                                          : 0

    implicitHeight: cardCol.implicitHeight + 20
    radius: 10
    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.7)

    // Colored left accent border
    Rectangle {
        width: 3
        height: parent.height
        anchors { left: parent.left; top: parent.top }
        radius: 2
        color: timerState === "running" ? Theme.primary : Theme.tertiary
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    ColumnLayout {
        id: cardCol
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            margins: 10
            leftMargin: 14
        }
        spacing: 4

        // ── Status row ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: {
                    const icon  = timerState === "running" ? "▶" : "⏸"
                    const state = timerState === "running" ? "RUNNING" : "PAUSED"
                    const modeLabel = card.isCountdown
                                      ? ("COUNTDOWN " + fmtTime(targetSeconds))
                                      : "STOPWATCH"
                    return icon + " " + state + " · " + modeLabel
                }
                color: timerState === "running" ? Theme.primary : Theme.tertiary
                font.pixelSize: 9
                font.weight: Font.Medium
                Layout.fillWidth: true
            }

            Row {
                spacing: 4

                // Edit button (hidden while confirming dismiss)
                Text {
                    visible: !card.confirmingDismiss
                    text:    "✏"
                    color:   Theme.on_surface_variant
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            card.editing = !card.editing
                            if (card.editing) editField.forceActiveFocus()
                        }
                    }
                }

                // Cancel confirm button
                Text {
                    visible: card.confirmingDismiss
                    text:    "Cancel"
                    color:   Theme.on_surface_variant
                    font.pixelSize: 9
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    card.confirmingDismiss = false
                    }
                }

                // Dismiss / Dismiss-confirm button
                Text {
                    text:  card.confirmingDismiss ? "Dismiss?" : "✕"
                    color: card.confirmingDismiss ? Theme.error : Theme.on_surface_variant
                    font.pixelSize:  card.confirmingDismiss ? 10 : 11
                    font.weight:     card.confirmingDismiss ? Font.Bold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (card.elapsedSeconds > 0 && !card.confirmingDismiss) {
                                card.confirmingDismiss = true
                            } else {
                                TimerService.dismissTimer(card.timerId)
                            }
                        }
                    }
                }
            }
        }

        // ── Label (static text or edit field) ─────────────────────────────
        Text {
            visible: !card.editing
            text:    card.label
            color:   Theme.on_surface
            font.pixelSize: 11
            elide:   Text.ElideRight
            Layout.fillWidth: true
        }

        TextInput {
            id: editField
            visible:    card.editing
            text:       card.label
            color:      Theme.on_surface
            font.pixelSize: 11
            Layout.fillWidth: true
            Keys.onReturnPressed: {
                TimerService.renameTimer(card.timerId, text)
                card.editing = false
            }
            Keys.onEscapePressed: card.editing = false
        }

        // ── Time display + controls ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text:       fmtTime(card.displaySecs)
                color:      card.isWarning ? Theme.error : Theme.on_surface
                font.pixelSize: 22
                font.family:    "JetBrainsMono Nerd Font"
                font.weight:    Font.Bold
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 6

                // Pause / Resume
                Rectangle {
                    width: 30; height: 24; radius: 6
                    color: Qt.rgba(Theme.surface_container_high.r,
                                   Theme.surface_container_high.g,
                                   Theme.surface_container_high.b, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text:  timerState === "running" ? "⏸" : "▶"
                        color: Theme.on_surface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (timerState === "running")
                                TimerService.pauseTimer(card.timerId)
                            else
                                TimerService.resumeTimer(card.timerId)
                        }
                    }
                }

                // Stop
                Rectangle {
                    width: 30; height: 24; radius: 6
                    color: Qt.rgba(Theme.surface_container_high.r,
                                   Theme.surface_container_high.g,
                                   Theme.surface_container_high.b, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text:  "■"
                        color: Theme.on_surface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    TimerService.stopTimer(card.timerId)
                    }
                }
            }
        }

        // ── Countdown progress bar ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: card.isCountdown
            height:  3
            radius:  2
            color: Qt.rgba(Theme.surface_container_high.r,
                           Theme.surface_container_high.g,
                           Theme.surface_container_high.b, 0.6)

            Rectangle {
                width:  parent.width * card.progress
                height: parent.height
                radius: parent.radius
                color:  card.isWarning ? Theme.error : Theme.primary
                Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.Linear } }
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    function fmtTime(secs) {
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        if (h > 0)
            return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
}
```

- [ ] **Step 2: Verify card renders (needs Task 7 form to create timers)**

Skip full verification until Task 7. Quick sanity: reload Quickshell, no QML errors.

- [ ] **Step 3: Commit**

```bash
git add modules/timer/TimerCard.qml
git commit -m "feat: implement TimerCard with pause/resume/stop, edit, dismiss-confirm, countdown progress"
```

---

## Task 7: NewTimerForm — creation form

After this task the full flow is testable end-to-end.

**Files:**
- Modify: `modules/timer/NewTimerForm.qml`

- [ ] **Step 1: Replace NewTimerForm.qml with full implementation**

File: `modules/timer/NewTimerForm.qml`
```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: form

    signal startTimer(string label, string mode, int targetSeconds)
    signal cancel()

    property string selectedMode: "stopwatch"
    property int    hours:   0
    property int    minutes: 0

    implicitHeight: formCol.implicitHeight + 24
    radius: 10
    color: Qt.rgba(Theme.surface_container_high.r,
                   Theme.surface_container_high.g,
                   Theme.surface_container_high.b, 0.5)

    ColumnLayout {
        id: formCol
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            margins: 12
        }
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "New Timer"
                color: Theme.on_surface
                font.pixelSize: 13
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            Text {
                text: "✕ Cancel"
                color: Theme.on_surface_variant
                font.pixelSize: 10
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: form.cancel()
                }
            }
        }

        // ── Label input ───────────────────────────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "PROJECT / LABEL"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
            }
            Rectangle {
                width: parent.width; height: 32
                radius: 8
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                border.color: labelField.activeFocus
                              ? Theme.primary
                              : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.5)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextInput {
                    id: labelField
                    anchors { fill: parent; margins: 8 }
                    color: Theme.on_surface
                    font.pixelSize: 12
                    placeholderText: "e.g. Gemini 3.1 prompt training"
                    placeholderTextColor: Theme.on_surface_variant
                    clip: true
                    Keys.onReturnPressed: if (text.trim().length > 0) form.submitTimer()
                }
            }
        }

        // ── Mode toggle ───────────────────────────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "MODE"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
            }
            Rectangle {
                width: parent.width; height: 30
                radius: 8
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)

                Row {
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        radius: 8
                        color: form.selectedMode === "stopwatch"
                               ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.9)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: "⏱ Stopwatch"
                            color: form.selectedMode === "stopwatch"
                                   ? Theme.on_primary_container : Theme.on_surface_variant
                            font.pixelSize: 11
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: form.selectedMode = "stopwatch"
                        }
                    }

                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        radius: 8
                        color: form.selectedMode === "countdown"
                               ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.9)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: "⏳ Countdown"
                            color: form.selectedMode === "countdown"
                                   ? Theme.on_primary_container : Theme.on_surface_variant
                            font.pixelSize: 11
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: form.selectedMode = "countdown"
                        }
                    }
                }
            }
        }

        // ── Duration picker (countdown only) ──────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            opacity: form.selectedMode === "countdown" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Text {
                text: "DURATION"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
            }
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2; height: 32
                    radius: 8
                    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        TextInput {
                            id: hoursField
                            width: 28
                            text: "0"
                            color: Theme.on_surface
                            font.pixelSize: 13
                            horizontalAlignment: TextInput.AlignRight
                            validator: IntValidator { bottom: 0; top: 23 }
                            enabled: form.selectedMode === "countdown"
                            onTextChanged: form.hours = parseInt(text) || 0
                        }
                        Text { text: "h"; color: Theme.on_surface_variant; font.pixelSize: 12 }
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2; height: 32
                    radius: 8
                    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        TextInput {
                            id: minutesField
                            width: 28
                            text: "00"
                            color: Theme.on_surface
                            font.pixelSize: 13
                            horizontalAlignment: TextInput.AlignRight
                            validator: IntValidator { bottom: 0; top: 59 }
                            enabled: form.selectedMode === "countdown"
                            onTextChanged: form.minutes = parseInt(text) || 0
                        }
                        Text { text: "m"; color: Theme.on_surface_variant; font.pixelSize: 12 }
                    }
                }
            }
        }

        // ── Start button ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 10
            color: labelField.text.trim().length > 0
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                   : Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g,
                             Theme.surface_container_high.b, 0.6)
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text:  "▶  Start Timer"
                color: labelField.text.trim().length > 0 ? Theme.on_primary : Theme.on_surface_variant
                font.pixelSize: 12
                font.weight: Font.Bold
            }

            MouseArea {
                anchors.fill: parent
                cursorShape:  labelField.text.trim().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled:      labelField.text.trim().length > 0
                onClicked:    form.submitTimer()
            }
        }
    }

    function submitTimer() {
        const lbl = labelField.text.trim()
        if (lbl.length === 0) return
        const targetSecs = form.selectedMode === "countdown"
                           ? (form.hours * 3600 + form.minutes * 60)
                           : 0
        form.startTimer(lbl, form.selectedMode, targetSecs)
        labelField.text = ""
        form.selectedMode = "stopwatch"
        form.hours = 0
        form.minutes = 0
        hoursField.text = "0"
        minutesField.text = "00"
    }
}
```

- [ ] **Step 2: Test end-to-end flow**

Reload Quickshell. Run through the full flow:

1. `$mainMod SHIFT T` → panel opens
2. Click `+ New` → NewTimerForm slides in with focus on label field
3. Type `"Gemini 3.1 training"`, click `▶ Start Timer`
   - Card appears, time ticks upward
   - Bar pill changes from `⏱ Timer` to `▶ 00:01` (ticking)
4. Click `+ New` again, add `"Client review"`, mode `Countdown`, `0h 01m`
   - Second card appears with `01:00` counting down and a progress bar
   - Bar pill shows `▶ <time> +1`
5. Click `⏸` on first card → turns amber, time stops
6. Click `▶` to resume
7. Click `■` on first card → card disappears, file written to `~/Desktop/timer_record/YYYY-MM.md`
8. Re-open panel → history section shows the logged entry
9. `Escape` → closes form if open, else closes panel

- [ ] **Step 3: Commit**

```bash
git add modules/timer/NewTimerForm.qml
git commit -m "feat: implement NewTimerForm with stopwatch/countdown mode, label input, duration picker"
```

---

## Self-Review Checklist

Before marking the implementation complete, verify:

- [ ] All 4 bar pill states render correctly (idle, 1 running, multi +N, countdown-red warning)
- [ ] Stopwatch timer ticks up; countdown ticks down; countdown auto-stops and logs at zero
- [ ] Pause/resume works; paused cards show amber border
- [ ] Stop (■) removes card and appends a row to `~/Desktop/timer_record/YYYY-MM.md`
- [ ] Dismiss (✕) shows confirm state for timers with elapsed > 0; instant for 0s timers
- [ ] Edit (✏) allows inline label rename; Enter saves, Escape cancels
- [ ] History section loads on panel open; shows up to 10 most recent entries
- [ ] `open file` link opens the markdown file in the default editor
- [ ] `$mainMod SHIFT T` keybinding toggles the panel
- [ ] Escape closes the new-timer form first, then the panel on a second press
- [ ] No QML errors in `journalctl --user -u quickshell -n 100`
