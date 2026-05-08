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
