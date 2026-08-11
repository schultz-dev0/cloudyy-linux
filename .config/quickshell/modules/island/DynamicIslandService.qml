pragma Singleton

import QtQuick
import Quickshell
import "IslandStatePolicy.js" as Policy

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
    // Mirror recording settings written by cloud-center (its own Quickshell
    // process — see shell.qml's FileView readers for how these get set).
    property string recFiletype: "mp4"
    property string recFilenamePattern: ""
    property int islandPreviewMs: 0
    property string playSoundScript: ""
    property var osdBurstComponent: null

    readonly property int osdBurstDurationMs: 2000
    property string _osdBurstId: ""

    signal osdBurstUpdated()
    signal shellLayoutChanged()
    signal transientPresented(var activity)
    signal transientUpdated(var activity)
    signal transientFinished(string activityId)

    function _queuedOsd(kind) {
        for (let i = 0; i < root._queue.length; i++) {
            const activity = root._queue[i];
            if (activity?.data?.activityType === "osd" && activity.data?.kind === kind)
                return activity;
        }
        return null;
    }

    function showOsdBurst(kind, icon, valueLabel, progress) {
        if (!root.osdBurstComponent)
            return;

        const prog = progress ?? 0;
        const act = root.currentActivity;

        if (act?.data?.activityType === "osd" && act.data?.kind === kind) {
            if (Policy.shouldReviveOsd(
                    act.data.activityType, act.data.kind, kind,
                    root._finishingActivityId === act.id))
                root._finishingActivityId = "";
            act.data.icon = icon;
            act.data.valueLabel = valueLabel;
            act.data.progress = prog;
            root._osdBurstId = act.id;
            root._startTimer(root.osdBurstDurationMs);
            root.osdBurstUpdated();
            root.transientUpdated(act);
            return act.id;
        }

        if (act?.data?.activityType === "osd") {
            root.remove(act.id);
            root._osdBurstId = "";
        }

        const queued = root._queuedOsd(kind);
        if (queued) {
            queued.data.icon = icon;
            queued.data.valueLabel = valueLabel;
            queued.data.progress = prog;
            root._osdBurstId = queued.id;
            return queued.id;
        }

        root._osdBurstId = root.push({
            contentComponent: root.osdBurstComponent,
            priority:         90,
            durationMs:       root.osdBurstDurationMs,
            data: {
                activityType: "osd",
                kind:         kind,
                icon:         icon,
                valueLabel:   valueLabel,
                progress:     prog
            }
        });
        return root._osdBurstId;
    }

    property string _recordingOutFile: ""
    property string _recordingPickerId: ""
    // Epoch ms when the current capture began (0 when idle). Used by the bar
    // recording pill for elapsed time; restore after qs restart uses Date.now().
    property real recordingStartedAt: 0
    readonly property bool recordingActive: _recordingOutFile !== ""

    // ── Public: read by the island shell ─────────────────────────────────────
    property var  currentActivity: null
    property int  pendingCount:    0

    readonly property int notificationIslandMaxMs:     5000
    readonly property int notificationIslandDefaultMs: 5000
    readonly property int screenshotPreviewExtraMs:    2000
    readonly property int recordPickerDurationMs:      10000
    // Temp PNG lifetime after capture (island may auto-hide sooner).
    readonly property int screenshotTmpRetentionSec:    300

    signal exitRequested()

    // True while a screenshot/recording preview drag may own a live QDrag.
    // Keeps the island on its current screen and blocks auto-dismiss teardown.
    property bool previewDragActive: false

    property var  _queue:  []
    property int  _serial: 0
    property string _finishingActivityId: ""
    property bool _currentHeld: false

    function beginPreviewDrag() {
        root.previewDragActive = true;
        root._timer.stop();
    }

    function endPreviewDrag() {
        root.previewDragActive = false;
    }

    function notificationIslandDurationMs(expireTimeoutSec) {
        if (expireTimeoutSec > 0)
            return Math.min(Math.round(expireTimeoutSec * 1000), root.notificationIslandMaxMs);
        return root.notificationIslandDefaultMs;
    }

    function screenshotPreviewDurationMs() {
        return root.notificationIslandDefaultMs + root.screenshotPreviewExtraMs;
    }

    // island_preview_ms setting overrides the default preview duration when set.
    function _previewDurationMs() {
        return root.islandPreviewMs > 0 ? root.islandPreviewMs : root.screenshotPreviewDurationMs();
    }

    property var _timer: Timer {
        repeat:   false
        running:  false
        onTriggered: root._onActivityTimerExpired()
    }

    function _onActivityTimerExpired() {
        if (root.previewDragActive)
            return;
        const act = root.currentActivity;
        if (act?.data?.activityType === "screenshot")
            root.dismissScreenshot(act.id);
        else if (act?.data?.activityType === "recording")
            root.dismissRecording(act.id);
        else if (act?.data?.activityType === "recordPicker")
            root.dismissRecordPicker(act.id);
        else
            root._finishCurrent();
    }

    function push(activityDef) {
        const serial = root._serial++;
        const id = "activity-" + serial;
        const requestedDuration = activityDef.durationMs ?? root.notificationIslandDefaultMs;
        const activity = {
            id:               id,
            serial:           serial,
            contentComponent: activityDef.contentComponent ?? null,
            priority:         activityDef.priority  ?? 10,
            // The island never holds passive, zero-duration activities.
            durationMs:       requestedDuration > 0
                                  ? requestedDuration
                                  : root.notificationIslandDefaultMs,
            data:             activityDef.data       ?? {}
        };

        const isNotif = activity.data?.activityType === "notification";
        const curIsNotif = root.currentActivity?.data?.activityType === "notification";

        if (curIsNotif && isNotif) {
            // FIFO: keep the visible notification until its timer ends.
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
            return id;
        }

        if (root.previewDragActive) {
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
            return id;
        }

        if (root.currentActivity === null) {
            root._present(activity);
        } else if (root._finishingActivityId) {
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
        } else if (activity.priority > root.currentActivity.priority) {
            const prev = root.currentActivity;
            root._timer.stop();
            root._insertQueued(prev);
            root.pendingCount = root._queue.length;
            root._present(activity);
        } else {
            root._extendCurrent();
            root._insertQueued(activity);
            root.pendingCount = root._queue.length;
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

    function clearAllNotifications() {
        function isNotif(activity) {
            return activity?.data?.activityType === "notification";
        }

        root._queue = root._queue.filter(a => !isNotif(a));
        root.pendingCount = root._queue.length;

        if (!isNotif(root.currentActivity))
            return;

        root._finishCurrent();
    }

    function popCurrent() {
        root._timer.stop();
        root._finishingActivityId = "";
        root._currentHeld = false;
        if (root._queue.length > 0) {
            root._queue.sort((a, b) => {
                const dp = b.priority - a.priority;
                if (dp !== 0)
                    return dp;
                return a.serial - b.serial;
            });
            const next = root._queue.shift();
            root.pendingCount    = root._queue.length;
            root._present(next);
        } else {
            root.currentActivity = null;
            root.pendingCount = 0;
        }
    }

    function _present(activity) {
        root._finishingActivityId = "";
        root._currentHeld = false;
        root.currentActivity = activity;
        root._startTimer(activity.durationMs);
        root.transientPresented(root.currentActivity);
    }

    function _finishCurrent() {
        const activityId = root.currentActivity?.id || "";
        if (!activityId || root._finishingActivityId === activityId)
            return;
        root._timer.stop();
        root._finishingActivityId = activityId;
        root.transientFinished(activityId);
        root.exitRequested();
    }

    function holdCurrent(activityId) {
        if (!root.currentActivity || root.currentActivity.id !== activityId)
            return;
        root._currentHeld = true;
        root._timer.stop();
    }

    function resumeCurrent(activityId) {
        if (!root.currentActivity || root.currentActivity.id !== activityId
                || !root._currentHeld || root._finishingActivityId)
            return;
        root._currentHeld = false;
        root._startTimer(root.currentActivity.durationMs);
    }

    function _startTimer(durationMs) {
        if (durationMs > 0) {
            root._timer.interval = durationMs;
            root._timer.restart();
        }
    }

    function _extendCurrent() {
        if (root.currentActivity && root.currentActivity.durationMs > 0
                && !root._currentHeld)
            root._timer.restart();
    }

    function _insertQueued(activity) {
        const q = root._queue.slice();
        q.push(activity);
        q.sort((a, b) => {
            const dp = b.priority - a.priority;
            if (dp !== 0)
                return dp;
            return a.serial - b.serial;
        });
        root._queue = q;
    }

    // ── Screenshot (contentComponent + procFactory provided by shell.qml) ───

    function _scheduleScreenshotFileCleanup(imagePath) {
        if (!imagePath)
            return;
        const sec = root.screenshotTmpRetentionSec;
        root._runShell("sleep " + sec + " && rm -f -- " + root._shellQuote(imagePath));
    }

    function showScreenshotPreview(imagePath, contentComponent, persistent) {
        const path = (imagePath || "").trim();
        if (!path || !contentComponent)
            return;

        if (!persistent)
            root._scheduleScreenshotFileCleanup(path);

        const activityId = root.push({
            contentComponent: contentComponent,
            priority:         25,
            durationMs:       root._previewDurationMs(),
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
        root.endPreviewDrag();
        delete root._screenshotSessions[activityId];
        root.remove(activityId);
    }

    function dismissCurrentScreenshot() {
        const act = root.currentActivity;
        if (act && act.data?.activityType === "screenshot")
            root.dismissScreenshot(act.id);
    }

    function dismissScreenshotAfterDrag(activityId) {
        root.endPreviewDrag();
        delete root._screenshotSessions[activityId];
        root.remove(activityId);
    }

    function copyScreenshotImage(imagePath) {
        if (!imagePath)
            return;
        root._runShell("wl-copy --type image/png < " + root._shellQuote(imagePath));
    }

    // Reads recording/edit_command at run time (no cached setting — Task 6 UI writes it).
    function editScreenshotImage(imagePath) {
        const path = (imagePath || "").trim();
        if (!path)
            return;
        const cmd = "cmd=$(cat \"$HOME/.config/cloud-center/settings/recording/edit_command\" 2>/dev/null); "
                    + "cmd=${cmd:-gio open}; "
                    + "if [ \"$cmd\" = \"xdg-open\" ]; then cmd='gio open'; fi; "
                    + "$cmd " + root._shellQuote(path);
        root._runShell(cmd);
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

    // Mirrors lib/recording_core.expand_filename_pattern's token set/format exactly.
    function _expandFilenamePattern(pattern) {
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const date = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
        const time = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
        return pattern
            .replace(/\{date\}/g, date)
            .replace(/\{time\}/g, time)
            .replace(/\{datetime\}/g, `${date}-${time}`);
    }

    function _nextRecordingFilename() {
        const ext = (root.recFiletype || "").trim() || "mp4";
        const pattern = (root.recFilenamePattern || "").trim();
        if (pattern) {
            const expanded = root._expandFilenamePattern(pattern);
            return /\.[A-Za-z0-9]+$/.test(expanded) ? expanded : `${expanded}.${ext}`;
        }
        const now = new Date();
        const pad = n => String(n).padStart(2, "0");
        const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}-`
                      + `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
        return `cloudyy-rec-${stamp}.${ext}`;
    }

    function toggleRecording() {
        if (root._recordingOutFile)
            root.stopRecording();
        else if (root._recordingPickerId
                 && (root.currentActivity?.id === root._recordingPickerId
                     || root._queue.some(a => a.id === root._recordingPickerId)))
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
            priority:         95,
            durationMs:       root.recordPickerDurationMs,
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
        // Never leave recordingsDir empty — FileView races can briefly clear it.
        if (!root.recordingsDir) {
            const home = Quickshell.env("HOME") || "";
            root.recordingsDir = home ? (home + "/Videos/Captures") : "";
        }
        if (!sel || !root.recordingsDir) {
            console.warn("recording: beginRecording aborted",
                         "selection=", sel, "recordingsDir=", root.recordingsDir);
            root.showOsdBurst("record-error", "", "Recording unavailable", 0);
            return;
        }

        root.dismissRecordPicker(pickerActivityId);

        const fname = root._nextRecordingFilename();
        const outFile = root.recordingsDir.replace(/\/$/, "") + "/" + fname;

        // cloudyy-recording-args prints "<front args> [-- <wf-recorder passthrough>]"
        // (audio only ever appears after `--` — hyprcap's own `-a` is unrelated,
        // it toggles notification actions). hyprcap needs the passthrough at the
        // very end, so `-N rec-start <selection>` must be spliced in before it,
        // not just appended to the whole string.
        //
        // hyprcap: options BEFORE command; selection as positional arg after
        // rec-start (not `-s` — hyprcap 1.6.0 breaks on -s outside a function).
        const cmd = "args=$(cloudyy-recording-args --kind rec --ensure-audio --filename "
                    + root._shellQuote(fname) + ") || exit 1\n"
                    + "eval \"arr=($args)\"\n"
                    + "front=(); rest=(); dd=0\n"
                    + "for tok in \"${arr[@]}\"; do\n"
                    + "    if [ \"$dd\" -eq 0 ] && [ \"$tok\" = \"--\" ]; then dd=1; continue; fi\n"
                    + "    if [ \"$dd\" -eq 0 ]; then front+=(\"$tok\"); else rest+=(\"$tok\"); fi\n"
                    + "done\n"
                    + "mkdir -p " + root._shellQuote(root.recordingsDir) + "\n"
                    + "if [ \"$dd\" -eq 1 ]; then\n"
                    + "    ( hyprcap \"${front[@]}\" -N rec-start " + root._shellQuote(sel)
                    + " -- \"${rest[@]}\" </dev/null >/dev/null 2>&1 & )\n"
                    + "else\n"
                    + "    ( hyprcap \"${front[@]}\" -N rec-start " + root._shellQuote(sel)
                    + " </dev/null >/dev/null 2>&1 & )\n"
                    + "fi\n";

        root._runShell(cmd, exitCode => {
            if (exitCode !== 0) {
                root.showOsdBurst("record-error", "", "Audio unavailable", 0);
                return;
            }
            root._recordingOutFile = outFile;
            root.recordingStartedAt = Date.now();
            root._writeRecordingState(outFile, sel);
        });
    }

    function stopRecording() {
        const outFile = root._recordingOutFile;
        const previewComp = root.recordingPreviewComponent;

        root._recordingOutFile = "";
        root.recordingStartedAt = 0;
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
            durationMs:       root._previewDurationMs(),
            data: {
                activityType: "recording",
                videoPath:    path
            }
        });

        root._recordingSessions[activityId] = { videoPath: path };
        return activityId;
    }

    function dismissRecording(activityId) {
        root.endPreviewDrag();
        delete root._recordingSessions[activityId];
        root._runShell("rm -f '/tmp/cloudyy-recording.preview.jpg'");
        root.remove(activityId);
    }

    function dismissCurrentRecording() {
        const act = root.currentActivity;
        if (act && act.data?.activityType === "recording")
            root.dismissRecording(act.id);
    }

    function dismissRecordingAfterDrag(activityId) {
        root.endPreviewDrag();
        delete root._recordingSessions[activityId];
        root._runShell("rm -f '/tmp/cloudyy-recording.preview.jpg'");
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
        // gio open respects GLib MIME defaults (mpv/Loupe); xdg-open often
        // hands media to a browser on this setup.
        root._runShell("gio open " + root._shellQuote(videoPath) + " 2>/dev/null || xdg-open " + root._shellQuote(videoPath));
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
