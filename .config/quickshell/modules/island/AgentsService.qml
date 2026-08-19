pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "AgentsPolicy.js" as Policy

Singleton {
    id: root

    property var _usageRecords: []
    property var _liveSessions: []
    property int _usageGeneration: 0
    property int _activeUsageGeneration: 0
    property int _sessionsGeneration: 0
    property int _activeSessionsGeneration: 0
    property bool _usagePending: false
    property bool _sessionsPending: false

    readonly property var usageRecords: root._usageRecords
    readonly property var liveSessions: root._liveSessions
    readonly property var oldestSession: Policy.oldestSession(root._liveSessions)
    readonly property bool hasData: Policy.hasData(root._usageRecords, root._liveSessions)

    function refreshUsage() {
        root._usageGeneration++;
        if (usageProc.running) {
            root._usagePending = true;
            return;
        }
        root._activeUsageGeneration = root._usageGeneration;
        usageProc.command = ["cloudyy-agents", "snapshot", "--json"];
        usageProc.running = true;
    }

    function refreshSessions() {
        root._sessionsGeneration++;
        if (sessionsProc.running) {
            root._sessionsPending = true;
            return;
        }
        root._activeSessionsGeneration = root._sessionsGeneration;
        sessionsProc.command = ["cloudyy-agents", "sessions", "--json"];
        sessionsProc.running = true;
    }

    function focusSession(agentId, pid, startedAt) {
        focusProc.command = ["cloudyy-agents", "focus",
            "--agent-id", agentId, "--pid", String(pid), "--started-at", startedAt];
        focusProc.running = true;
    }

    function _finishUsage() {
        if (root._usagePending) {
            root._usagePending = false;
            root.refreshUsage();
        }
    }

    function _finishSessions() {
        if (root._sessionsPending) {
            root._sessionsPending = false;
            root.refreshSessions();
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refreshSessions()
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refreshUsage()
    }

    Process {
        id: usageProc
        running: false
        stdout: StdioCollector { id: usageCollector }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                const result = Policy.parseUsageSnapshot(usageCollector.text,
                    root._usageRecords, root._activeUsageGeneration,
                    root._usageGeneration, Date.now());
                if (result.accepted)
                    root._usageRecords = result.records;
            }
            root._finishUsage();
        }
    }

    Process {
        id: sessionsProc
        running: false
        stdout: StdioCollector { id: sessionsCollector }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0) {
                const result = Policy.parseSessionsSnapshot(sessionsCollector.text,
                    root._liveSessions, root._activeSessionsGeneration,
                    root._sessionsGeneration);
                if (result.accepted)
                    root._liveSessions = result.sessions;
            }
            root._finishSessions();
        }
    }

    Process {
        id: focusProc
        running: false
    }

    Component.onCompleted: {
        root.refreshUsage();
        root.refreshSessions();
    }
}
