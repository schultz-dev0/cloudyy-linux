import QtQuick
import Quickshell.Io
import "../components"
import "../components/RecordingState.js" as RecordingState
import "../services" as S
import ".."

Flickable {
    id: recordingPage
    required property var page

    contentWidth: width
    contentHeight: content.implicitHeight + 54
    clip: true

    property var snapshot: RecordingState.emptySnapshot()
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: ""
    property bool watchStarted: false
    property string pendingDeletePath: ""

    // Same path as bindings.lua Print / Shift+Print / Alt+Print:
    // hl.dispatch(hl.dsp.exec_cmd("cloudyy-screenshot-capture …"))
    Process {
        id: captureLauncher
        running: false
    }

    function launchCapture(flag) {
        const cmd = "cloudyy-screenshot-capture " + flag;
        captureLauncher.running = false;
        captureLauncher.command = [
            "hyprctl", "eval",
            'hl.dispatch(hl.dsp.exec_cmd("' + cmd + '"))'
        ];
        captureLauncher.running = true;
    }

    // Free-text settings fields load their draft once (guarded by
    // settingsLoaded) instead of continuously re-binding to the live
    // snapshot, so a watch tick landing mid-edit can't clobber what the user
    // is typing. Select/switch-backed settings below bind straight to the
    // live snapshot since choosing an option can't race with typing.
    property bool settingsLoaded: false
    property string screenshotsDirDraft: ""
    property string recordingsDirDraft: ""
    property string codecDraft: ""
    property string filenamePatternDraft: ""
    property string editCommandDraft: "xdg-open"
    property string islandPreviewMsDraft: "7000"

    readonly property var settings: snapshot.settings || ({})
    readonly property var audioInputs: snapshot.audio_inputs || ({ mics: [], desktops: [] })
    readonly property var recordingStatus: snapshot.recording || ({ active: false, out_file: "", selection: "" })
    readonly property var gallery: snapshot.gallery || []
    readonly property bool recordingActive: recordingStatus.active === true
    readonly property bool hasError: snapshot.error !== "" && snapshot.error !== undefined
    readonly property bool bannerVisible: hasError || recordingActive

    readonly property var fpsOptions: [24, 30, 60, 120]
    readonly property var filetypeOptions: ["mp4", "mkv", "webm", "mov"]

    function applySnapshot(next) {
        if (!next)
            return;
        snapshot = RecordingState.clone(next);
        if (snapshot.stale === true) {
            statusMessage = String(snapshot.error || "Recording status could not be refreshed");
            return;
        }
        statusMessage = String(snapshot.error || "");
        if (!settingsLoaded) {
            const loaded = snapshot.settings || {};
            screenshotsDirDraft = String(loaded.screenshots_dir || "");
            recordingsDirDraft = String(loaded.recordings_dir || "");
            codecDraft = String(loaded.rec_codec || "");
            filenamePatternDraft = String(loaded.rec_filename_pattern || "");
            editCommandDraft = String(loaded.edit_command || "xdg-open");
            islandPreviewMsDraft = String(loaded.island_preview_ms || 7000);
            settingsLoaded = true;
        }
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_recording_snapshot", {}, function(result) {
            recordingPage.applySnapshot(result);
            if (startWatchAfter && !recordingPage.watchStarted) {
                recordingPage.watchStarted = true;
                S.Backend.request("start_recording_watch", {}, function(watchSnapshot) {
                    recordingPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    recordingPage.statusMessage = String(
                        (error && (error.message || error.error))
                        || "Recording live updates could not start"
                    );
                });
            }
        }, function(error) {
            recordingPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Recording status could not be refreshed"
            );
        });
    }

    function sendAction(action, value, target) {
        const actionId = String(nextActionId++);
        const generation = nextGeneration++;
        S.Backend.request("run_recording_action", {
            action: action,
            target: target || action,
            value: value,
            action_id: actionId,
            generation: generation,
        }, function(result) {
            if (result && result.queued === true)
                return;
            recordingPage.statusMessage = String(
                (result && (result.message || result.error))
                || "Recording action was rejected"
            );
        }, function(error) {
            recordingPage.statusMessage = String(
                (error && (error.message || error.error))
                || "Recording action failed"
            );
        });
    }

    function commitSetting(key, value) {
        sendAction("set_setting", { key: key, value: value }, "setting:" + key);
    }

    function commitIslandPreviewMs(text) {
        const value = parseInt(text, 10);
        if (!isFinite(value) || value <= 0) {
            islandPreviewMsDraft = String(recordingPage.settings.island_preview_ms || 7000);
            return;
        }
        islandPreviewMsDraft = String(value);
        commitSetting("island_preview_ms", value);
    }

    function requestGalleryAction(action, path) {
        if (action === "delete") {
            recordingPage.pendingDeletePath = path;
            deleteDialog.open();
            return;
        }
        recordingPage.sendAction(action, path, action + ":" + path);
    }

    function confirmDelete() {
        deleteDialog.close();
        recordingPage.sendAction("delete", recordingPage.pendingDeletePath,
            "delete:" + recordingPage.pendingDeletePath);
        recordingPage.pendingDeletePath = "";
    }

    Component.onCompleted: requestSnapshot(true)
    Component.onDestruction: S.Backend.request("stop_recording_watch", {}, null)

    Connections {
        target: S.Backend
        function onRecordingSnapshotEvent(next) {
            recordingPage.applySnapshot(next);
        }
        function onRecordingActionDoneEvent(actionId, target, generation, ok,
                                            staleTarget, message) {
            if (message)
                recordingPage.statusMessage = String(message);
        }
    }

    CloudDialog {
        id: deleteDialog
        width: 420
        // Header (72) + divider + footer (59); no body content.
        height: 132
        heading: "Delete file?"
        supportingText: recordingPage.pendingDeletePath
        primaryText: "Delete"
        secondaryText: "Cancel"
        onPrimaryClicked: recordingPage.confirmDelete()
        onSecondaryClicked: recordingPage.pendingDeletePath = ""
    }

    Column {
        id: content
        width: Math.min(recordingPage.width - 56, 760)
        x: (recordingPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: content.width
            height: 46
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: recordingPage.page.title || "Recording"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; weight: Font.Bold
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Refresh"
                glyph: "󰑐"
                subtle: true
                compact: true
                onClicked: recordingPage.requestSnapshot(false)
            }
        }

        Rectangle {
            visible: recordingPage.bannerVisible
            width: content.width
            height: bannerText.implicitHeight + 20
            radius: 2
            color: recordingPage.hasError ? Theme.error_container : Theme.primary_container
            border { width: 1; color: Theme.hairline }

            Row {
                anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                spacing: 8
                Rectangle {
                    visible: !recordingPage.hasError && recordingPage.recordingActive
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: Theme.error
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: recordingPage.recordingActive
                        NumberAnimation { from: 1; to: 0.25; duration: 700 }
                        NumberAnimation { from: 0.25; to: 1; duration: 700 }
                    }
                }
                Text {
                    id: bannerText
                    width: parent.width - 24
                    text: recordingPage.hasError
                        ? String(recordingPage.snapshot.error)
                        : "Recording… " + (recordingPage.recordingStatus.selection
                            || recordingPage.recordingStatus.out_file || "")
                    wrapMode: Text.WordWrap
                    color: recordingPage.hasError ? Theme.error : Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Controls" })

            Item {
                width: parent.width
                height: 56
                Row {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    CloudButton {
                        text: "Screenshot"
                        glyph: "\u{f0100}"
                        onClicked: recordingPage.launchCapture("--screenshot")
                    }
                    CloudButton {
                        text: "Save Screenshot"
                        glyph: "\u{f0d5d}"
                        onClicked: recordingPage.launchCapture("--screenshot-save")
                    }
                }
                CloudButton {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: recordingPage.recordingActive ? "Stop Recording" : "Start Recording"
                    glyph: "\u{f044b}"
                    primary: !recordingPage.recordingActive
                    danger: recordingPage.recordingActive
                    onClicked: recordingPage.launchCapture("--record")
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Paths" })

            Column {
                width: parent.width
                spacing: 10
                topPadding: 6
                bottomPadding: 10

                Item {
                    width: parent.width
                    height: 60
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Screenshots Directory"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.screenshotsDirDraft
                            placeholderText: "~/Pictures/Screenshots"
                            onAccepted: recordingPage.commitSetting("screenshots_dir", text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitSetting("screenshots_dir", text)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 60
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Recordings Directory"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.recordingsDirDraft
                            placeholderText: "~/Videos/Captures"
                            onAccepted: recordingPage.commitSetting("recordings_dir", text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitSetting("recordings_dir", text)
                        }
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Audio Inputs" })

            RecordingAudioPicker {
                width: parent.width
                settings: recordingPage.settings
                audioInputs: recordingPage.audioInputs
                onSettingChanged: (key, value) => recordingPage.commitSetting(key, value)
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Encode" })

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48
                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "Frame Rate"
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    CloudSelect {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 140
                        compact: true
                        options: recordingPage.fpsOptions
                        currentIndex: recordingPage.fpsOptions.indexOf(Number(recordingPage.settings.rec_fps))
                        onActivated: index => recordingPage.commitSetting("rec_fps", recordingPage.fpsOptions[index])
                    }
                }

                Item {
                    width: parent.width
                    height: 48
                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "File Type"
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    CloudSelect {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 140
                        compact: true
                        options: recordingPage.filetypeOptions
                        currentIndex: recordingPage.filetypeOptions.indexOf(String(recordingPage.settings.rec_filetype))
                        onActivated: index => recordingPage.commitSetting("rec_filetype", recordingPage.filetypeOptions[index])
                    }
                }

                Item {
                    width: parent.width
                    height: 60
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Codec"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.codecDraft
                            placeholderText: "auto"
                            onAccepted: recordingPage.commitSetting("rec_codec", text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitSetting("rec_codec", text)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 70
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Filename Pattern"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.filenamePatternDraft
                            placeholderText: "{date}-{time}"
                            onAccepted: recordingPage.commitSetting("rec_filename_pattern", text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitSetting("rec_filename_pattern", text)
                        }
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Behavior" })

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 60
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Island Preview Duration (ms)"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.islandPreviewMsDraft
                            onAccepted: recordingPage.commitIslandPreviewMs(text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitIslandPreviewMs(text)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 48
                    Text {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "Auto-Copy After Capture"
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    CloudSwitch {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        checked: recordingPage.settings.auto_copy === true
                        onToggled: checked => recordingPage.commitSetting("auto_copy", checked)
                    }
                }

                Item {
                    width: parent.width
                    height: 70
                    Column {
                        anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                        spacing: 4
                        Text {
                            text: "Edit Command"
                            color: Theme.textPrimary
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        CloudTextField {
                            width: parent.width
                            compact: true
                            text: recordingPage.editCommandDraft
                            placeholderText: "xdg-open"
                            onAccepted: recordingPage.commitSetting("edit_command", text)
                            onActiveFocusChanged: if (!activeFocus)
                                recordingPage.commitSetting("edit_command", text)
                        }
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Gallery" })

            RecordingGalleryGrid {
                width: parent.width
                items: recordingPage.gallery
                onActionRequested: (action, path) => recordingPage.requestGalleryAction(action, path)
                onEnsureThumbNeeded: path => recordingPage.sendAction("ensure_thumb", path, "ensure_thumb:" + path)
            }
        }

        Text {
            visible: recordingPage.statusMessage !== "" && !recordingPage.bannerVisible
            width: content.width
            text: recordingPage.statusMessage
            wrapMode: Text.WordWrap
            color: recordingPage.snapshot.stale === true ? Theme.error : Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                   hintingPreference: Font.PreferVerticalHinting }
            leftPadding: 4
        }
    }
}
