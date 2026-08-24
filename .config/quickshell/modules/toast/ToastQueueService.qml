pragma Singleton

import QtQuick
import "ToastQueuePolicy.js" as Policy

QtObject {
    id: root

    // Set from shell.qml — QtObject cannot host Component/Process children.
    property var procFactory: null
    property string playSoundScript: ""

    readonly property int notificationDefaultMs: 5000
    readonly property int notificationMaxMs: 5000
    readonly property int osdBurstDurationMs: 2000

    property var currentActivity: null
    property var _queue: []
    property int _serial: 0
    property string _finishingActivityId: ""
    property string _osdBurstId: ""

    signal currentActivityUpdated()
    signal currentActivityFinished(string activityId)

    function notificationDurationMs(expireTimeoutSec) {
        if (expireTimeoutSec > 0)
            return Math.min(Math.round(expireTimeoutSec * 1000), root.notificationMaxMs);
        return root.notificationDefaultMs;
    }

    function showOsdBurst(kind, icon, valueLabel, progress) {
        const prog = progress ?? 0;
        const act = root.currentActivity;

        if (act?.data?.activityType === "osd" && act.data?.kind === kind) {
            act.data.icon = icon;
            act.data.valueLabel = valueLabel;
            act.data.progress = prog;
            root._osdBurstId = act.id;
            root._startTimer(root.osdBurstDurationMs);
            root.currentActivityUpdated();
            return act.id;
        }

        if (act?.data?.activityType === "osd") {
            root.remove(act.id);
            root._osdBurstId = "";
        }

        const queued = Policy.findQueuedOsd(root._queue, kind);
        if (queued) {
            queued.data.icon = icon;
            queued.data.valueLabel = valueLabel;
            queued.data.progress = prog;
            root._osdBurstId = queued.id;
            return queued.id;
        }

        root._osdBurstId = root.push({
            priority: 90,
            durationMs: root.osdBurstDurationMs,
            data: { activityType: "osd", kind: kind, icon: icon, valueLabel: valueLabel, progress: prog }
        });
        return root._osdBurstId;
    }

    function push(activityDef) {
        const serial = root._serial++;
        const id = "toast-" + serial;
        const requestedDuration = activityDef.durationMs ?? root.notificationDefaultMs;
        const activity = {
            id: id,
            serial: serial,
            priority: activityDef.priority ?? 10,
            durationMs: requestedDuration > 0 ? requestedDuration : root.notificationDefaultMs,
            data: activityDef.data ?? {}
        };

        const decision = Policy.decidePush(root.currentActivity, root._finishingActivityId, activity);
        if (decision.action === "queue") {
            root._insertQueued(activity);
        } else if (decision.action === "extend") {
            root._extendCurrent();
            root._insertQueued(activity);
        } else if (decision.bumpCurrent) {
            const prev = root.currentActivity;
            root._timer.stop();
            root._insertQueued(prev);
            root._present(activity);
        } else {
            root._present(activity);
        }
        return id;
    }

    function remove(id) {
        if (root._osdBurstId === id)
            root._osdBurstId = "";
        if (root.currentActivity && root.currentActivity.id === id) {
            root._finishCurrent();
            return;
        }
        root._queue = root._queue.filter(a => a.id !== id);
    }

    function removeForNotification(notificationId) {
        function matches(activity) {
            return activity?.data?.notificationId === notificationId;
        }
        if (root.currentActivity && matches(root.currentActivity)) {
            root.remove(root.currentActivity.id);
            return;
        }
        root._queue = root._queue.filter(a => !matches(a));
    }

    function clearAllNotifications() {
        function isNotif(activity) {
            return activity?.data?.activityType === "notification";
        }
        root._queue = root._queue.filter(a => !isNotif(a));
        if (isNotif(root.currentActivity))
            root._finishCurrent();
    }

    function _present(activity) {
        root._finishingActivityId = "";
        root.currentActivity = activity;
        root._startTimer(activity.durationMs);
    }

    function _finishCurrent() {
        const activityId = root.currentActivity?.id || "";
        if (!activityId || root._finishingActivityId === activityId)
            return;
        root._timer.stop();
        root._finishingActivityId = activityId;
        root._popCurrent();
    }

    function _popCurrent() {
        root._finishingActivityId = "";
        if (root._queue.length > 0) {
            const sorted = Policy.sortQueue(root._queue);
            const next = sorted[0];
            root._queue = sorted.slice(1);
            root._present(next);
        } else {
            root.currentActivity = null;
        }
    }

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
        root._queue = Policy.sortQueue(root._queue.concat([activity]));
    }

    property var _timer: Timer {
        repeat: false
        running: false
        onTriggered: root._popCurrent()
    }

    function playNotifSound() {
        root._playSound("notif", 0);
    }

    function _playSound(kind, delayMs) {
        if (!root.playSoundScript)
            return;
        const ms = Math.max(0, delayMs | 0);
        root._runShell("(" + root._shellQuote(root.playSoundScript) + " "
                       + root._shellQuote(kind) + " " + ms + ") </dev/null >/dev/null 2>&1 &");
    }

    function _shellQuote(path) {
        return "'" + String(path).replace(/'/g, "'\\''") + "'";
    }

    function _runShell(cmd, onDone) {
        if (!root.procFactory)
            return null;
        const proc = root.procFactory.createObject(root, {
            command: ["sh", "-c", cmd]
        });
        proc.exited.connect(exitCode => {
            if (onDone)
                onDone(exitCode);
            proc.destroy();
        });
        proc.running = true;
        return proc;
    }
}
