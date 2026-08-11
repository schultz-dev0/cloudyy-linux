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
    readonly property string homeDir: Quickshell.env("HOME") || ""
    property bool loaded: false
    property string persistenceError: ""
    property bool _saveInFlight: false
    property string _pendingSavePayload: ""
    readonly property bool hasRunningTimers: runningCount > 0

    signal timerCompleted(var timer)
    signal timerAboutToRemove(string timerId)
    signal historyChanged
    signal persistenceFailed(string message)

    // ── Computed properties ───────────────────────────────────────────────
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

    // ── Per-second tick ───────────────────────────────────────────────────
    readonly property Timer ticker: Timer {
        interval: 1000
        running: root.hasRunningTimers
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
            root._scheduleSave()
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
        p.exited.connect((exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0)
                root.historyChanged();
            p.destroy();
        })
        p.running = true
    }

    // ── Persistence ─────────────────────────────────────────────────────
    readonly property Timer _saveDebounce: Timer {
        interval: 250
        repeat: false
        onTriggered: root._saveNow()
    }

    function _scheduleSave() {
        if (!root.loaded) return
        _saveDebounce.restart()
    }

    function _saveNow() {
        if (!root.loaded) return
        const payload = JSON.stringify({
            version: 1,
            savedAt: Math.floor(Date.now() / 1000),
            timers: root._serializeTimers()
        })
        if (root._saveInFlight) {
            root._pendingSavePayload = payload;
            return;
        }
        root._startSave(payload);
    }

    function _startSave(payload) {
        root._saveInFlight = true;
        saveProc.environment = ({ "QS_DATA": payload })
        saveProc.running = true
    }

    function _serializeTimers() {
        const list = []
        for (let i = 0; i < timers.count; i++) {
            const t = timers.get(i)
            list.push({
                timerId:        t.timerId,
                label:          t.label,
                mode:           t.mode,
                targetSeconds:  t.targetSeconds,
                elapsedSeconds: t.elapsedSeconds,
                timerState:     t.timerState
            })
        }
        return list
    }

    function _restoreTimers(rawList, savedAt) {
        const now = Math.floor(Date.now() / 1000)
        const delta = savedAt > 0 ? Math.max(0, now - savedAt) : 0
        let changed = false

        for (let i = 0; i < rawList.length; i++) {
            const raw = rawList[i]
            if (!raw || !raw.timerId) {
                changed = true
                continue
            }

            let elapsed = parseInt(raw.elapsedSeconds, 10) || 0
            const state = raw.timerState === "paused" ? "paused" : "running"
            if (state === "running" && delta > 0)
                elapsed += delta

            const mode = raw.mode === "countdown" ? "countdown" : "stopwatch"
            const target = parseInt(raw.targetSeconds, 10) || 0
            const label = `${raw.label ?? ""}`.trim() || "Timer"

            if (mode === "countdown" && state === "running" && target > 0 && elapsed >= target) {
                const snapshot = root._timerSnapshot({
                    timerId: `${raw.timerId}`,
                    label: label,
                    mode: mode,
                    targetSeconds: target,
                    elapsedSeconds: target,
                    timerState: state
                });
                root.timerCompleted(snapshot);
                root._writeLog(snapshot.label, snapshot.elapsedSeconds,
                               snapshot.mode, snapshot.targetSeconds)
                changed = true
                continue
            }

            timers.append({
                timerId:        `${raw.timerId}`,
                label:          label,
                mode:           mode,
                targetSeconds:  target,
                elapsedSeconds: elapsed,
                timerState:     state
            })
        }
        return changed
    }

    // ── Internal helpers ──────────────────────────────────────────────────
    function _findTimer(timerId) {
        for (let i = 0; i < timers.count; i++)
            if (timers.get(i).timerId === timerId) return i
        return -1
    }

    function _finishTimer(idx) {
        const t = timers.get(idx)
        const snapshot = root._timerSnapshot(t);
        root.timerAboutToRemove(snapshot.timerId);
        root.timerCompleted(snapshot);
        root._writeLog(snapshot.label, snapshot.elapsedSeconds,
                       snapshot.mode, snapshot.targetSeconds)
        idx = root._findTimer(snapshot.timerId)
        if (idx >= 0)
            timers.remove(idx)
        _scheduleSave()
    }

    function _timerSnapshot(timer) {
        return Object.freeze({
            timerId: timer.timerId,
            label: timer.label,
            mode: timer.mode,
            targetSeconds: timer.targetSeconds,
            elapsedSeconds: timer.elapsedSeconds,
            timerState: timer.timerState
        });
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
        _scheduleSave()
    }

    function pauseTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) {
            timers.setProperty(idx, "timerState", "paused")
            _scheduleSave()
        }
    }

    function resumeTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) {
            timers.setProperty(idx, "timerState", "running")
            _scheduleSave()
        }
    }

    function resetTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) {
            timers.setProperty(idx, "elapsedSeconds", 0)
            _scheduleSave()
        }
    }

    function stopTimer(timerId) {
        const idx = _findTimer(timerId)
        if (idx >= 0) _finishTimer(idx)
    }

    function dismissTimer(timerId) {
        let idx = _findTimer(timerId)
        if (idx >= 0) {
            root.timerAboutToRemove(timerId)
            idx = _findTimer(timerId)
            if (idx >= 0)
                timers.remove(idx)
            _scheduleSave()
        }
    }

    function renameTimer(timerId, newLabel) {
        const idx = _findTimer(timerId)
        if (idx >= 0) {
            timers.setProperty(idx, "label", newLabel)
            _scheduleSave()
        }
    }

    function fmtTime(secs) {
        secs = Math.floor(secs)
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        if (h > 0)
            return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }

    Process {
        id: initProc
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/timer\";" +
            "mkdir -p \"$dir\";" +
            "[ -r \"$dir/active.json\" ] && cat \"$dir/active.json\" || echo '{}'"
        ]
        stdout: StdioCollector {
            id: initCollector
            onStreamFinished: {
                const text = initCollector.text.trim()
                let restoredWithCleanup = false
                if (text && text !== "{}") {
                    try {
                        const parsed = JSON.parse(text)
                        const list = Array.isArray(parsed.timers) ? parsed.timers : []
                        const savedAt = parseInt(parsed.savedAt, 10) || 0
                        if (list.length > 0)
                            restoredWithCleanup = root._restoreTimers(list, savedAt)
                    } catch (err) {
                        console.warn("timer: failed to parse active.json:", err)
                    }
                }
                root.loaded = true
                if (restoredWithCleanup)
                    root._scheduleSave()
            }
        }
    }

    Process {
        id: saveProc
        running: false
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/timer\";" +
            "mkdir -p \"$dir\";" +
            "printf '%s' \"$QS_DATA\" > \"$dir/active.json\""
        ]
        onExited: (exitCode, exitStatus) => {
            const succeeded = exitCode === 0 && exitStatus === 0;
            const pending = root._pendingSavePayload;
            root._pendingSavePayload = "";
            root._saveInFlight = false;

            if (pending) {
                if (succeeded)
                    root.persistenceError = "";
                root._startSave(pending);
                return;
            }
            if (succeeded) {
                root.persistenceError = "";
                return;
            }
            root.persistenceError = "Could not save active timers (exit "
                + exitCode + ", status " + exitStatus + ")";
            console.warn("timer:", root.persistenceError);
            root.persistenceFailed(root.persistenceError);
        }
    }

    Component.onCompleted: {
        initProc.running = true
    }
}
