pragma Singleton

import QtQuick
import Quickshell
import "../toast" as QuickToast
import "../shelf" as QuickShelf

QtObject {
    id: root

    // Set from shell.qml — QtObject cannot host Component/Process children.
    property var procFactory: null

    property string recordingsDir: ""
    // Mirror recording settings written by cloud-center (its own Quickshell
    // process — see shell.qml's FileView readers for how these get set).
    property string recFiletype: "mp4"
    property string recFilenamePattern: ""
    property string playSoundScript: ""

    property string _recordingOutFile: ""
    property bool recordingStarting: false
    property var _recordingLaunchProc: null
    property var _recordingStartWaitProc: null
    property int _recordingLaunchSerial: 0
    property string _recordingLaunchPidFile: ""
    property var _recordingStateProc: null
    // Epoch ms when the current capture began (0 when idle). Used by the bar
    // recording pill for elapsed time; restore after qs restart uses Date.now().
    property real recordingStartedAt: 0
    readonly property bool recordingActive: _recordingOutFile !== ""

    readonly property string _recordingStateFile: "/tmp/cloudyy-recording.state"
    readonly property string _recordingPathFile: "/tmp/cloudyy-recording.path"
    readonly property int screencapRecordStopDelayMs: 60

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
        if (root.recordingStarting || root._recordingOutFile)
            root.stopRecording();
        else
            root.beginRecording("region", "");
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
            QuickToast.ToastQueueService.showOsdBurst("record-error", "", "Recording unavailable", 0);
            return;
        }

        const fname = root._nextRecordingFilename();
        const outFile = root.recordingsDir.replace(/\/$/, "") + "/" + fname;
        const launchSerial = ++root._recordingLaunchSerial;
        const launchPidFile = "/tmp/cloudyy-recording-launch." + launchSerial + ".pid";
        root._recordingLaunchPidFile = launchPidFile;

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
                     + "printf '%s' \"$$\" > " + root._shellQuote(launchPidFile) + "\n"
                     + "if [ \"$dd\" -eq 1 ]; then\n"
                     + "    exec hyprcap \"${front[@]}\" -N rec-start " + root._shellQuote(sel)
                     + " -- \"${rest[@]}\" </dev/null >/dev/null 2>&1\n"
                     + "else\n"
                     + "    exec hyprcap \"${front[@]}\" -N rec-start " + root._shellQuote(sel)
                     + " </dev/null >/dev/null 2>&1\n"
                     + "fi\n";

        root.recordingStarting = true;
        root._recordingLaunchProc = root._runShell(cmd, exitCode => {
            if (launchSerial !== root._recordingLaunchSerial)
                return;
            root._recordingLaunchProc = null;
            root._recordingLaunchPidFile = "";
            root._runShell("rm -f " + root._shellQuote(launchPidFile));
            if (!root.recordingStarting && !root.recordingActive)
                return;
            const wasActive = root.recordingActive;
            root.recordingStarting = false;
            root._recordingOutFile = "";
            root.recordingStartedAt = 0;
            root._clearRecordingState();
            QuickToast.ToastQueueService.showOsdBurst("record-error", "",
                              wasActive ? "Recording stopped unexpectedly" : "Recording cancelled", 0);
        });

        const runtimeDir = Quickshell.env("XDG_RUNTIME_DIR") || "/run";
        const pidFile = runtimeDir.replace(/\/$/, "") + "/hyprcap_rec.pid";
        const waitCmd = "for i in $(seq 1 6000); do "
                        + "pid=$(cat " + root._shellQuote(pidFile) + " 2>/dev/null || true); "
                        + "[ -n \"$pid\" ] && kill -0 \"$pid\" 2>/dev/null && exit 0; "
                        + "sleep 0.1; done; exit 1";
        root._recordingStartWaitProc = root._runShell(waitCmd, exitCode => {
            if (launchSerial !== root._recordingLaunchSerial)
                return;
            root._recordingStartWaitProc = null;
            if (!root.recordingStarting)
                return;
            if (exitCode !== 0) {
                root.recordingStarting = false;
                root._cancelRecordingLaunch();
                QuickToast.ToastQueueService.showOsdBurst("record-error", "", "Recording selection timed out", 0);
                return;
            }
            root.recordingStarting = false;
            root._recordingOutFile = outFile;
            root.recordingStartedAt = Date.now();
            root._writeRecordingState(outFile, sel);
        });
    }

    function stopRecording() {
        const outFile = root._recordingOutFile;

        root.recordingStarting = false;
        root._recordingOutFile = "";
        root.recordingStartedAt = 0;
        root._clearRecordingState();

        if (!outFile) {
            root._cancelRecordingLaunch();
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
            root.showRecordingPreview(outFile);
        });
    }

    function _writeRecordingState(outFile, selection) {
        const body = "RECORDING=1\nOUT_FILE=" + outFile + "\nSELECTION=" + selection + "\n";
        const tmp = root._recordingStateFile + ".tmp";
        const proc = root._runShell("printf %s " + root._shellQuote(body)
                       + " > " + root._shellQuote(tmp)
                       + " && mv -f " + root._shellQuote(tmp) + " "
                       + root._shellQuote(root._recordingStateFile), () => {
            if (root._recordingStateProc === proc)
                root._recordingStateProc = null;
        });
        root._recordingStateProc = proc;
    }

    function _cancelRecordingLaunch() {
        const proc = root._recordingLaunchProc;
        const waiter = root._recordingStartWaitProc;
        const launchPidFile = root._recordingLaunchPidFile;
        root._recordingLaunchSerial++;
        root._recordingLaunchProc = null;
        root._recordingStartWaitProc = null;
        root._recordingLaunchPidFile = "";
        const pidFile = root._shellQuote(launchPidFile);
        root._runShell("pid=$(cat " + pidFile + " 2>/dev/null || true); "
                       + "if [ -n \"$pid\" ]; then "
                       + "pkill -TERM -P \"$pid\" 2>/dev/null || true; "
                       + "kill -TERM \"$pid\" 2>/dev/null || true; fi; "
                       + "rm -f " + pidFile);
        if (proc)
            proc.signal(15);
        if (waiter)
            waiter.signal(15);
    }

    function _clearRecordingState() {
        if (root._recordingStateProc) {
            root._recordingStateProc.signal(15);
            root._recordingStateProc = null;
        }
        root._runShell("rm -f " + root._shellQuote(root._recordingStateFile)
                       + " " + root._shellQuote(root._recordingStateFile + ".tmp"));
    }

    function showRecordingPreview(videoPath) {
        QuickShelf.PreviewShelfService.addRecording(videoPath);
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
