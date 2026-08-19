pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "TimerProviderPolicy.js" as Policy

Singleton {
    id: root

    property bool loaded: false
    property string providerError: ""
    property int presentationEpoch: Math.floor(Date.now() / 1000)
    readonly property ListModel timers: ListModel {}
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") || "") + "/.local/state") + "/cloudyy/timers"
    readonly property bool busy: listProc.running || commandProc.running
        || _commandQueue.length > 0
    property bool _refreshPending: false
    property string _commandError: ""
    property var _commandQueue: []

    signal timerCompleted(var timer)
    signal timerAboutToRemove(string timerId)

    readonly property int runningCount: {
        let count = 0;
        for (let i = 0; i < timers.count; i++) {
            if (timers.get(i).timerState === "running")
                count++;
        }
        return count;
    }

    readonly property var nearestCountdown: {
        const list = root._timerArray();
        return Policy.nearestCountdown(list);
    }

    readonly property var primaryTimer: {
        const list = root._timerArray();
        return Policy.primaryTimer(list);
    }

    function _timerArray() {
        const list = [];
        for (let i = 0; i < root.timers.count; i++)
            list.push(root.timers.get(i));
        return list;
    }

    function _sameStructure(nextTimers) {
        if (root.timers.count !== nextTimers.length)
            return false;
        for (let i = 0; i < nextTimers.length; i++) {
            if (root.timers.get(i).timerId !== nextTimers[i].timerId)
                return false;
        }
        return true;
    }

    function _replaceTimers(nextTimers, completedTimers) {
        const completedById = {};
        const nextById = {};
        for (let i = 0; i < completedTimers.length; i++)
            completedById[completedTimers[i].timerId] = completedTimers[i];
        for (let i = 0; i < nextTimers.length; i++)
            nextById[nextTimers[i].timerId] = true;

        if (root._sameStructure(nextTimers)) {
            for (let i = 0; i < nextTimers.length; i++)
                root.timers.set(i, nextTimers[i]);
            return;
        }

        for (let i = 0; i < root.timers.count; i++) {
            const current = root.timers.get(i);
            root.timerAboutToRemove(current.timerId);
            if (!nextById[current.timerId] && completedById[current.timerId])
                root.timerCompleted(completedById[current.timerId]);
        }
        root.timers.clear();
        for (let i = 0; i < nextTimers.length; i++)
            root.timers.append(nextTimers[i]);
    }

    function refresh() {
        if (listProc.running) {
            root._refreshPending = true;
            return;
        }
        listProc.command = ["cloudyy-timer", "list", "--json"];
        listProc.running = true;
    }

    function _run(command) {
        root._commandQueue = root._commandQueue.concat([command]);
        root._startNextCommand();
    }

    function _startNextCommand() {
        if (listProc.running || commandProc.running || root._commandQueue.length === 0)
            return;
        const command = root._commandQueue[0];
        root._commandQueue = root._commandQueue.slice(1);
        root._commandError = "";
        root.providerError = "";
        commandProc.command = command;
        commandProc.running = true;
    }

    function createCountdown(label, durationSeconds) {
        root._run(["cloudyy-timer", "create", "--label", label,
            "--duration", String(durationSeconds), "--json"]);
    }

    function startStopwatch(label) {
        root._run(["cloudyy-timer", "stopwatch-start", "--label", label, "--json"]);
    }

    function pause(timerId, mode) {
        root._run(["cloudyy-timer", mode === "stopwatch" ? "stopwatch-pause" : "pause", timerId]);
    }

    function resume(timerId) {
        root._run(["cloudyy-timer", "resume", timerId]);
    }

    function reset(timerId, mode) {
        root._run(["cloudyy-timer", mode === "stopwatch" ? "stopwatch-reset" : "reset", timerId]);
    }

    function rename(timerId, label) {
        root._run(["cloudyy-timer", "rename", timerId, label]);
    }

    function remove(timerId) {
        root._run(["cloudyy-timer", "delete", timerId]);
    }

    function stop(timerId) {
        root._run(["cloudyy-timer", "stop", timerId, "--json"]);
    }

    function displaySeconds(timer) {
        if (!timer)
            return 0;
        return Policy.displaySeconds(timer, root.presentationEpoch);
    }

    function fmtTime(secs) {
        secs = Math.max(0, Math.floor(secs));
        const hours = Math.floor(secs / 3600);
        const minutes = Math.floor((secs % 3600) / 60);
        const seconds = secs % 60;
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0")
                + ":" + String(seconds).padStart(2, "0");
        return String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
    }

    Timer {
        interval: 1000
        running: root.runningCount > 0
        repeat: true
        onTriggered: root.presentationEpoch = Math.floor(Date.now() / 1000)
    }

    FileView {
        path: root.stateDir + "/state.json"
        watchChanges: true
        onFileChanged: root.refresh()
    }

    Process {
        id: listProc
        running: false
        stdout: StdioCollector { id: listOutput }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                const result = Policy.parseSnapshot(listOutput.text, root._timerArray());
                if (result.accepted) {
                    root._replaceTimers(result.timers, result.completed);
                    root.providerError = root._commandError;
                } else {
                    root.providerError = result.error;
                }
            } else {
                root.providerError = "Could not read timers (exit " + exitCode
                    + ", status " + exitStatus + ")";
            }
            root.loaded = true;
            if (root._refreshPending) {
                root._refreshPending = false;
                root.refresh();
            } else {
                root._startNextCommand();
            }
        }
    }

    Process {
        id: commandProc
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                root._commandError = "";
            } else {
                root._commandError = "Timer command failed (exit " + exitCode
                    + ", status " + exitStatus + ")";
                root.providerError = root._commandError;
            }
            root.refresh();
        }
    }

    Component.onCompleted: root.refresh()
}
