pragma Singleton

import QtQuick

QtObject {
    id: root

    // Set from shell.qml — QtObject cannot host Component/Process children.
    property var procFactory: null
    property string playSoundScript: ""

    readonly property int notificationDefaultMs: 5000
    readonly property int notificationMaxMs: 5000
    readonly property int osdBurstDurationMs: 2000

    // Every toast shows at once, stacked — no queue, no preemption. Same-kind
    // OSD bursts (e.g. holding a volume key) update the existing entry in
    // place instead of stacking duplicates.
    property var activeToasts: []
    property int _serial: 0

    function notificationDurationMs(expireTimeoutSec) {
        if (expireTimeoutSec > 0)
            return Math.min(Math.round(expireTimeoutSec * 1000), root.notificationMaxMs);
        return root.notificationDefaultMs;
    }

    function showOsdBurst(kind, icon, valueLabel, progress) {
        const prog = progress ?? 0;
        const idx = root.activeToasts.findIndex(t => t.data?.activityType === "osd" && t.data?.kind === kind);

        if (idx !== -1) {
            const updated = root.activeToasts.slice();
            const prev = updated[idx];
            updated[idx] = Object.assign({}, prev, {
                data: Object.assign({}, prev.data, { icon: icon, valueLabel: valueLabel, progress: prog }),
                expiresAt: Date.now() + root.osdBurstDurationMs
            });
            root.activeToasts = updated;
            return updated[idx].id;
        }

        return root.push({
            durationMs: root.osdBurstDurationMs,
            data: { activityType: "osd", kind: kind, icon: icon, valueLabel: valueLabel, progress: prog }
        });
    }

    function push(activityDef) {
        const serial = root._serial++;
        const id = "toast-" + serial;
        const durationMs = activityDef.durationMs > 0 ? activityDef.durationMs : root.notificationDefaultMs;
        const toast = {
            id: id,
            serial: serial,
            data: activityDef.data ?? {},
            expiresAt: Date.now() + durationMs
        };
        root.activeToasts = root.activeToasts.concat([toast]);
        root._tickTimer.running = true;
        return id;
    }

    function remove(id) {
        root.activeToasts = root.activeToasts.filter(t => t.id !== id);
    }

    function removeForNotification(notificationId) {
        root.activeToasts = root.activeToasts.filter(t => t.data?.notificationId !== notificationId);
    }

    function clearAllNotifications() {
        root.activeToasts = root.activeToasts.filter(t => t.data?.activityType !== "notification");
    }

    // Single shared timer sweeps expired toasts rather than one Timer per
    // entry — simpler than managing N dynamic Timer objects for a plain
    // array of data, and 250ms resolution is plenty for a UI element.
    property var _tickTimer: Timer {
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            const now = Date.now();
            const remaining = root.activeToasts.filter(t => t.expiresAt > now);
            if (remaining.length !== root.activeToasts.length)
                root.activeToasts = remaining;
            if (root.activeToasts.length === 0)
                root._tickTimer.running = false;
        }
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
