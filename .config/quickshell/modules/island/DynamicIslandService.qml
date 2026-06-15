pragma Singleton

import QtQuick

QtObject {
    id: root

    // Set from shell.qml — QtObject cannot host Component/Process children.
    property var procFactory: null

    property var _screenshotSessions: ({})
    property var _recordingSessions: ({})

    // Set from shell.qml
    property var recordPickerComponent: null
    property var recordingPreviewComponent: null
    property string recordingsDir: ""
    property string playSoundScript: ""

    property string _recordingOutFile: ""
    property string _recordingPickerId: ""

    // ── Public: read by the island shell ─────────────────────────────────────
    property var  currentActivity: null
    property int  pendingCount:    0

    readonly property int notificationIslandMaxMs:     5000
    readonly property int notificationIslandDefaultMs: 5000
    readonly property int screenshotPreviewExtraMs:    2000
    // Temp PNG lifetime after capture (island may auto-hide sooner).
    readonly property int screenshotTmpRetentionSec:    300

    signal exitRequested()

    property var  _queue:  []
    property int  _serial: 0

    function notificationIslandDurationMs(expireTimeoutSec) {
        if (expireTimeoutSec > 0)
            return Math.min(Math.round(expireTimeoutSec * 1000), root.notificationIslandMaxMs);
        return root.notificationIslandDefaultMs;
    }

    function screenshotPreviewDurationMs() {
        return root.notificationIslandDefaultMs + root.screenshotPreviewExtraMs;
    }

    property var _timer: Timer {
        repeat:   false
        running:  false
        onTriggered: root._onActivityTimerExpired()
    }

    function _onActivityTimerExpired() {
        const act = root.currentActivity;
        if (act?.data?.activityType === "screenshot")
            root.dismissScreenshot(act.id);
        else
            root.exitRequested();
    }

    function push(activityDef) {
        const id = "activity-" + root._serial++;
        const activity = {
            id:               id,
            contentComponent: activityDef.contentComponent ?? null,
            priority:         activityDef.priority  ?? 10,
            durationMs:       activityDef.durationMs ?? 5000,
            data:             activityDef.data       ?? {}
        };

        if (root.currentActivity === null) {
            root.currentActivity = activity;
            root._startTimer(activity.durationMs);
        } else if (activity.priority > root.currentActivity.priority) {
            const prev = root.currentActivity;
            root._timer.stop();
            root.currentActivity = activity;
            root._insertQueued(prev);
            root.pendingCount = root._queue.length;
            root._startTimer(activity.durationMs);
        } else {
            root._extendCurrent();
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
        }

        return id;
    }

    function remove(id) {
        if (root.currentActivity && root.currentActivity.id === id) {
            root._timer.stop();
            root.exitRequested();
            return;
        }
        root._queue = root._queue.filter(a => a.id !== id);
        root.pendingCount = root._queue.length;
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
        root.pendingCount = root._queue.length;
    }

    function popCurrent() {
        root._timer.stop();
        if (root._queue.length > 0) {
            root._queue.sort((a, b) => b.priority - a.priority);
            root.currentActivity = root._queue.shift();
            root.pendingCount    = root._queue.length;
            root._startTimer(root.currentActivity.durationMs);
        } else {
            root.currentActivity = null;
            root.pendingCount    = 0;
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
        const q = root._queue.slice();
        q.push(activity);
        q.sort((a, b) => b.priority - a.priority);
        root._queue = q;
    }

    // ── Screenshot (contentComponent + procFactory provided by shell.qml) ───

    function _scheduleScreenshotFileCleanup(imagePath) {
        if (!imagePath)
            return;
        const sec = root.screenshotTmpRetentionSec;
        root._runShell("sleep " + sec + " && rm -f -- " + root._shellQuote(imagePath));
    }

    function showScreenshotPreview(imagePath, contentComponent) {
        const path = (imagePath || "").trim();
        if (!path || !contentComponent)
            return;

        root._scheduleScreenshotFileCleanup(path);

        const activityId = root.push({
            contentComponent: contentComponent,
            priority:         25,
            durationMs:       root.screenshotPreviewDurationMs(),
            data: {
                activityType: "screenshot",
                imagePath:    path
            }
        });

        root._screenshotSessions[activityId] = { imagePath: path };
        root.playScreencapSound(root.screencapScreenshotDelayMs);
        return activityId;
    }

    function dismissScreenshot(activityId) {
        delete root._screenshotSessions[activityId];
        root.remove(activityId);
    }

    function dismissCurrentScreenshot() {
        const act = root.currentActivity;
        if (act && act.data?.activityType === "screenshot")
            root.dismissScreenshot(act.id);
    }

    function dismissScreenshotAfterDrag(activityId) {
        delete root._screenshotSessions[activityId];
        root.remove(activityId);
    }

    function copyScreenshotImage(imagePath) {
        if (!imagePath)
            return;
        root._runShell("wl-copy --type image/png < " + root._shellQuote(imagePath));
    }

    // ── Recording (picker + active indicator + preview; hyprcap owns capture) ───

    readonly property string _recordingStateFile: "/tmp/cloudyy-recording.state"
    readonly property string _recordingPathFile: "/tmp/cloudyy-recording.path"
    // Screencap cue timing (ms). Tune if the sound lands in recordings or feels late.
    readonly property int screencapScreenshotDelayMs: 10
    readonly property int screencapRecordStopDelayMs: 60

    function _selectionLabel(selection) {
        switch (selection) {
        case "region": return "Area";
        case "monitor:active": return "Active monitor";
        case "monitor": return "Monitor";
        default: return selection || "Capture";
        }
    }

    function _nextRecordingFilename() {
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}-`
                      + `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
        return `cloudyy-rec-${stamp}.mp4`;
    }

    function toggleRecording() {
        if (root._recordingOutFile)
            root.stopRecording();
        else if (root._recordingPickerId)
            root.dismissRecordPicker(root._recordingPickerId);
        else
            root.showRecordPicker();
    }

    function showRecordPicker() {
        if (!root.recordPickerComponent)
            return;

        if (root._recordingPickerId)
            root.remove(root._recordingPickerId);

        root._recordingPickerId = root.push({
            contentComponent: root.recordPickerComponent,
            priority:         26,
            durationMs:       0,
            data: { activityType: "recordPicker" }
        });
    }

    function playNotifSound() {
        root._playSound("notif", 0);
    }

    function playScreencapSound(delayMs) {
        root._playSound("screencap", delayMs ?? 0);
    }

    function _playSound(kind, delayMs) {
        if (!root.playSoundScript)
            return;
        const ms = Math.max(0, delayMs | 0);
        root._runShell("(" + root._shellQuote(root.playSoundScript) + " "
                       + root._shellQuote(kind) + " " + ms + ") </dev/null >/dev/null 2>&1 &");
    }

    function dismissRecordPicker(activityId) {
        if (activityId && root._recordingPickerId === activityId)
            root._recordingPickerId = "";
        root.remove(activityId || root._recordingPickerId);
    }

    function beginRecording(selection, pickerActivityId) {
        const sel = (selection || "").trim();
        if (!sel || !root.recordingsDir)
            return;

        root.dismissRecordPicker(pickerActivityId);

        const fname = root._nextRecordingFilename();
        const outFile = root.recordingsDir.replace(/\/$/, "") + "/" + fname;

        root._recordingOutFile = outFile;
        root._writeRecordingState(outFile, sel);

        // hyprcap: options BEFORE command; selection as positional arg after
        // rec-start (not `-s` — hyprcap 1.6.0 breaks on -s outside a function).
        const cmd = "mkdir -p " + root._shellQuote(root.recordingsDir)
                    + " && ( hyprcap -w -o " + root._shellQuote(root.recordingsDir)
                    + " -f " + root._shellQuote(fname)
                    + " -N rec-start " + root._shellQuote(sel)
                    + " </dev/null >/dev/null 2>&1 & )";
        root._runShell(cmd);
    }

    function stopRecording() {
        const outFile = root._recordingOutFile;
        const previewComp = root.recordingPreviewComponent;

        root._recordingOutFile = "";
        root._clearRecordingState();

        if (!outFile || !previewComp) {
            root._runShell("hyprcap rec-stop -N 2>/dev/null || true");
            return;
        }

        const waitCmd = "hyprcap rec-stop -N 2>/dev/null || hyprcap rec-stop 2>/dev/null || true; "
                        + "outfile=" + root._shellQuote(outFile) + "; "
                        + "for i in $(seq 1 60); do "
                        + "[ -f \"$outfile\" ] && [ -s \"$outfile\" ] && break; "
                        + "sleep 0.25; done; "
                        + "if [ -f \"$outfile\" ] && [ -s \"$outfile\" ]; then "
                        + "printf '%s' \"$outfile\" > " + root._shellQuote(root._recordingPathFile) + "; "
                        + "exit 0; fi; exit 1";

        root._runShell(waitCmd, exitCode => {
            if (exitCode !== 0) {
                console.warn("recording: no output file at", outFile);
                return;
            }
            root.playScreencapSound(root.screencapRecordStopDelayMs);
            root.showRecordingPreview(outFile, previewComp);
        });
    }

    function _writeRecordingState(outFile, selection) {
        const body = "RECORDING=1\nOUT_FILE=" + outFile + "\nSELECTION=" + selection + "\n";
        root._runShell("printf %s > " + root._shellQuote(root._recordingStateFile) + " "
                       + root._shellQuote(body));
    }

    function _clearRecordingState() {
        root._runShell("rm -f " + root._shellQuote(root._recordingStateFile));
    }

    function showRecordingPreview(videoPath, contentComponent) {
        const path = (videoPath || "").trim();
        if (!path || !contentComponent)
            return;

        const activityId = root.push({
            contentComponent: contentComponent,
            priority:         25,
            durationMs:       0,
            data: {
                activityType: "recording",
                videoPath:    path
            }
        });

        root._recordingSessions[activityId] = { videoPath: path };
        return activityId;
    }

    function dismissRecording(activityId) {
        delete root._recordingSessions[activityId];
        root.remove(activityId);
    }

    function dismissCurrentRecording() {
        const act = root.currentActivity;
        if (act && act.data?.activityType === "recording")
            root.dismissRecording(act.id);
    }

    function dismissRecordingAfterDrag(activityId) {
        delete root._recordingSessions[activityId];
        root.remove(activityId);
    }

    function copyRecordingPath(videoPath) {
        if (!videoPath)
            return;
        root._runShell("printf %s " + root._shellQuote(videoPath) + " | wl-copy");
    }

    function openRecordingVideo(videoPath) {
        if (!videoPath)
            return;
        root._runShell("xdg-open " + root._shellQuote(videoPath));
    }

    function _shellQuote(path) {
        return "'" + String(path).replace(/'/g, "'\\''") + "'";
    }

    function _runShell(cmd, onDone) {
        if (!root.procFactory)
            return;
        const proc = root.procFactory.createObject(root, {
            command: ["sh", "-c", cmd]
        });
        proc.exited.connect(exitCode => {
            if (onDone)
                onDone(exitCode);
            proc.destroy();
        });
        proc.running = true;
    }
}
