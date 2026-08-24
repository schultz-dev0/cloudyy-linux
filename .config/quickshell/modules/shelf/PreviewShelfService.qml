pragma Singleton

import QtQuick
import "../recording" as QuickRecording

QtObject {
    id: root

    property var pendingCaptures: []
    property int _serial: 0

    // Set from shell.qml — QtObject cannot host Component/Process children.
    property var procFactory: null

    readonly property int screenshotCleanupDelayMs: 300000 // 5 min, matches deleted island cleanup timing

    function addScreenshot(path) {
        const id = root._add("screenshot", path);
        QuickRecording.RecordingService.playScreencapSound(0);
        root._scheduleScreenshotCleanup(path);
        return id;
    }

    function addRecording(path) {
        return root._add("recording", path);
    }

    // Screenshots write to /tmp on every capture and are never referenced again
    // once the shelf card is dismissed — clean up the temp file after a delay,
    // matching the deleted DynamicIslandService._scheduleScreenshotFileCleanup().
    // Recordings are real user files (saved under ~/Videos/Captures) and are
    // deliberately never cleaned up here.
    function _scheduleScreenshotCleanup(path) {
        if (!root.procFactory || !path)
            return;
        const proc = root.procFactory.createObject(root, {
            command: ["sh", "-c", "sleep " + (root.screenshotCleanupDelayMs / 1000)
                      + " && rm -f -- " + root._shellQuote(path)]
        });
        proc.exited.connect(() => proc.destroy());
        proc.running = true;
    }

    function _shellQuote(path) {
        return "'" + String(path).replace(/'/g, "'\\''") + "'";
    }

    function _add(kind, path) {
        const id = "capture-" + (root._serial++);
        root.pendingCaptures = root.pendingCaptures.concat([{
            id: id,
            kind: kind,
            path: path,
            addedAt: Date.now()
        }]);
        return id;
    }

    function dismiss(id) {
        root.pendingCaptures = root.pendingCaptures.filter(c => c.id !== id);
    }

    function dismissAll() {
        root.pendingCaptures = [];
    }
}
