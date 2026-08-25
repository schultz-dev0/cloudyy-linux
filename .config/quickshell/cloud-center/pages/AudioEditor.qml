import QtQuick
import "../components"
import "../components/AudioState.js" as AudioState
import "../services" as S
import ".."

Flickable {
    id: audioPage
    required property var page

    contentWidth: width
    contentHeight: content.implicitHeight + 54
    clip: true

    property var snapshot: ({ sinks: [], sources: [], streams: [], cards: [],
                              automation: ({}), service: ({}) })
    property var pending: ({})
    property var busyTargets: ({})
    property string selectedKind: "sink"
    property string selectedSink: ""
    property string selectedSource: ""
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: "Loading audio devices…"

    property bool watchStarted: false
    property var actionMeta: ({})
    property bool servicePromptHandled: false
    property bool servicePromptRequestPending: false
    property bool hardwareExpanded: false
    property bool automationExpanded: false

    readonly property var activeDevices: selectedKind === "sink"
        ? (snapshot.sinks || []) : (snapshot.sources || [])
    readonly property int outputCount: (snapshot.sinks || []).length
    readonly property int inputCount: (snapshot.sources || []).length
    readonly property int streamCount: (snapshot.streams || []).length
    readonly property bool initialRetryAvailable: snapshot.stale === true
        && outputCount + inputCount === 0 && String(snapshot.error || "") !== ""

    function clone(value) {
        return AudioState.clone(value);
    }

    function hasDevices(value) {
        return ((value.sinks || []).length + (value.sources || []).length) > 0;
    }

    function applySnapshot(next) {
        if (!next) return;
        if (next.stale === true) {
            // A stale snapshot deliberately leaves working controls intact. The
            // initial empty failure is retained only so its Retry affordance has
            // an error to describe.
            if (!hasDevices(snapshot))
                snapshot = clone(next);
            statusMessage = String(next.error || "Audio devices could not be refreshed");
            return;
        }

        snapshot = clone(next);
        selectedSink = AudioState.stableSelection(snapshot.sinks, selectedSink, "name");
        selectedSource = AudioState.stableSelection(snapshot.sources, selectedSource, "name");
        statusMessage = String(snapshot.error || "");
        maybePromptForService();
    }

    function maybePromptForService() {
        if (servicePromptHandled || !AudioState.shouldPromptService(snapshot)) return;
        servicePromptHandled = true;
        serviceMigrationDialog.open();
    }

    function serviceMessage(value, fallback) {
        if (!value) return fallback;
        return String(value.message || value.error || fallback);
    }

    function handleServiceRequestError(error) {
        servicePromptRequestPending = false;
        statusMessage = serviceMessage(error, "Could not enable audio service");
        if (serviceMigrationDialog.visible)
            serviceMigrationDialog.close();
    }

    function enableServiceFromMigration() {
        servicePromptRequestPending = true;
        try {
            S.Backend.request("enable_audio_autoswitch_service", {
                enable: true,
                dismiss_prompt: true,
            }, function(result) {
                servicePromptRequestPending = false;
                if (result && result.snapshot)
                    audioPage.applySnapshot(result.snapshot);
                if (!result || result.ok !== true)
                    statusMessage = audioPage.serviceMessage(result, "Could not enable audio service");
                serviceMigrationDialog.close();
            }, function(error) { audioPage.handleServiceRequestError(error); });
        } catch (error) {
            handleServiceRequestError(error);
        }
    }

    function dismissServiceMigration() {
        try {
            S.Backend.request("enable_audio_autoswitch_service", {
                enable: false,
                dismiss_prompt: true,
            }, function(result) {
                if (result && result.snapshot)
                    audioPage.applySnapshot(result.snapshot);
                else if (!result || result.ok !== true)
                    statusMessage = audioPage.serviceMessage(result, "Could not postpone audio service setup");
            }, function(error) {
                statusMessage = audioPage.serviceMessage(error, "Could not postpone audio service setup");
            });
        } catch (error) {
            statusMessage = String(error);
        }
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_audio_snapshot", {}, function(result) {
            audioPage.applySnapshot(result);
            if (startWatchAfter && !audioPage.watchStarted) {
                audioPage.watchStarted = true;
                S.Backend.request("start_audio_watch", {}, function(watchSnapshot) {
                    audioPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    audioPage.statusMessage = audioPage.serviceMessage(
                        error, "Audio live updates could not start"
                    );
                });
            }
        }, function(error) {
            audioPage.statusMessage = audioPage.serviceMessage(error, "Audio devices could not be refreshed");
        });
    }

    function retrySnapshot() {
        statusMessage = "Refreshing audio devices…";
        requestSnapshot(!watchStarted);
    }

    function refreshSnapshotQuietly() {
        requestSnapshot(!watchStarted);
    }

    function allocateGeneration() {
        return nextGeneration++;
    }

    function setBusyTarget(target, actionId) {
        const next = clone(busyTargets);
        const key = String(target);
        const actions = next[key] === undefined ? ({}) : clone(next[key]);
        actions[String(actionId)] = true;
        next[key] = actions;
        busyTargets = next;
    }

    function clearBusyTarget(target, actionId) {
        const next = clone(busyTargets);
        const key = String(target);
        if (next[key] === undefined) return;
        const actions = clone(next[key]);
        delete actions[String(actionId)];
        if (Object.keys(actions).length === 0)
            delete next[key];
        else
            next[key] = actions;
        busyTargets = next;
    }

    function sendAction(action, target, value, fieldKey, generation) {
        const actionId = String(nextActionId++);
        const actionGeneration = allocateGeneration();
        const isBusyAction = action !== "set_sink_volume" && action !== "set_source_volume"
            && action !== "set_stream_volume" && action !== "set_sink_mute"
            && action !== "set_source_mute" && action !== "set_stream_mute";
        pending = AudioState.setPending(pending, fieldKey, actionGeneration, value);
        const nextMeta = clone(actionMeta);
        nextMeta[actionId] = {
            fieldKey: fieldKey,
            target: String(target),
            generation: actionGeneration,
            busy: isBusyAction,
        };
        actionMeta = nextMeta;
        if (isBusyAction)
            setBusyTarget(target, actionId);
        try {
            S.Backend.request("run_audio_action", {
                action: action,
                target: target,
                value: value,
                action_id: actionId,
                generation: actionGeneration,
            }, function(result) { audioPage.handleActionReply(actionId, result); },
            function(error) { audioPage.handleActionError(actionId, error); });
        } catch (error) {
            rejectAction(actionId, false, String(error));
        }
    }

    function handleActionReply(actionId, result) {
        if (result && (result.queued === true || result.ok === true)) return;
        const staleTarget = Boolean(result && (result.stale_target === true || result.staleTarget === true));
        const message = result && (result.message || result.error)
            ? String(result.message || result.error) : "Audio action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function handleActionError(actionId, error) {
        const staleTarget = Boolean(error && (error.stale_target === true || error.staleTarget === true));
        const message = error && (error.message || error.error)
            ? String(error.message || error.error) : "Audio action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function rejectAction(actionId, staleTarget, message) {
        const meta = actionMeta[String(actionId)];
        if (meta === undefined) return;
        finishAction(actionId, meta.target, meta.generation, false, staleTarget, message);
    }

    function finishAction(actionId, target, generation, ok, staleTarget, message) {
        const id = String(actionId);
        const meta = actionMeta[id];
        if (meta === undefined
            || String(target) !== String(meta.target)
            || Number(generation) !== Number(meta.generation)) return;
        pending = AudioState.clearCompleted(pending, meta.fieldKey, generation);
        if (meta.busy)
            clearBusyTarget(meta.target, id);
        const nextMeta = clone(actionMeta);
        delete nextMeta[id];
        actionMeta = nextMeta;
        if (!ok && !staleTarget)
            statusMessage = String(message || "Audio action failed");
        if (staleTarget)
            refreshSnapshotQuietly();
    }

    function applyServiceStatus(status, message) {
        const next = clone(snapshot);
        next.service = status || ({});
        snapshot = next;
        if (message)
            statusMessage = String(message);
        maybePromptForService();
    }

    Component.onCompleted: requestSnapshot(true)
    Component.onDestruction: S.Backend.request("stop_audio_watch", {}, null)

    Connections {
        target: S.Backend
        function onAudioSnapshotEvent(next) { audioPage.applySnapshot(next); }
        function onAudioActionDoneEvent(actionId, target, generation, ok,
                                        staleTarget, message) {
            audioPage.finishAction(actionId, target, generation, ok,
                                   staleTarget, message);
        }
        function onAudioServiceStatusEvent(status, message) {
            audioPage.applyServiceStatus(status, message);
        }
    }

    CloudDialog {
        id: serviceMigrationDialog
        width: 460
        height: 238
        heading: "Keep audio switching active?"
        supportingText: "Cloud Center can enable the user service required for automatic output switching after this window closes."
        primaryText: "Enable Service"
        secondaryText: "Not Now"
        primaryEnabled: !audioPage.servicePromptRequestPending
        onPrimaryClicked: audioPage.enableServiceFromMigration()
        onSecondaryClicked: audioPage.dismissServiceMigration()
    }

    Column {
        id: content
        width: Math.min(audioPage.width - 56, 760)
        x: (audioPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: content.width
            height: 46
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    text: audioPage.page.title
                    color: Theme.text
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; weight: Font.Bold
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    text: outputCount + " outputs · " + inputCount + " inputs · " + streamCount + " applications"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
            CloudButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Refresh"
                glyph: "󰑐"
                subtle: true
                compact: true
                onClicked: audioPage.retrySnapshot()
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Output & Input" })

            Item {
                width: parent.width
                height: 52
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Show"
                    color: Theme.text
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 12
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                CloudSelect {
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    width: 160
                    compact: true
                    options: [
                        { id: "sink", label: "Output" },
                        { id: "source", label: "Input" },
                    ]
                    textRole: "label"
                    currentIndex: audioPage.selectedKind === "source" ? 1 : 0
                    onActivated: index => {
                        const option = options[index];
                        if (option)
                            audioPage.selectedKind = option.id;
                    }
                }
            }

            AudioDevicePanel {
                width: parent.width
                devices: audioPage.activeDevices
                kind: audioPage.selectedKind
                selectedId: audioPage.selectedKind === "sink"
                    ? audioPage.selectedSink : audioPage.selectedSource
                pending: audioPage.pending
                busyTargets: audioPage.busyTargets
                visible: audioPage.activeDevices.length > 0
                onSelected: id => {
                    if (audioPage.selectedKind === "sink") audioPage.selectedSink = id;
                    else audioPage.selectedSource = id;
                }
                onActionRequested: (action, target, value, fieldKey, generation) =>
                    audioPage.sendAction(action, target, value, fieldKey, generation)
            }

            Item {
                visible: audioPage.activeDevices.length === 0
                width: parent.width
                height: 86
                Text {
                    anchors { left: parent.left; leftMargin: 14; right: retryButton.left; rightMargin: 12
                              verticalCenter: parent.verticalCenter }
                    text: audioPage.initialRetryAvailable
                        ? String(audioPage.snapshot.error) : "No "
                            + (audioPage.selectedKind === "sink" ? "output" : "input") + " devices detected"
                    wrapMode: Text.WordWrap
                    color: audioPage.initialRetryAvailable ? Theme.error : Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                           hintingPreference: Font.PreferVerticalHinting }
                }
                CloudButton {
                    id: retryButton
                    visible: audioPage.initialRetryAvailable
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Retry"
                    compact: true
                    primary: true
                    onClicked: audioPage.retrySnapshot()
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "" })

            Text {
                width: parent.width
                height: 42
                leftPadding: 14
                verticalAlignment: Text.AlignVCenter
                text: "Applications"
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }

            Repeater {
                model: audioPage.snapshot.streams || []
                delegate: AudioApplicationRow {
                    required property var modelData
                    width: parent.width
                    stream: modelData
                    sinks: audioPage.snapshot.sinks || []
                    pending: audioPage.pending
                    busy: Boolean(audioPage.busyTargets[String(modelData.index)])
                    onActionRequested: (action, target, value, fieldKey, generation) =>
                        audioPage.sendAction(action, target, value, fieldKey, generation)
                }
            }

            Item {
                visible: (audioPage.snapshot.streams || []).length === 0
                width: parent.width
                height: 72
                Text {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: Text.AlignVCenter
                    text: "No active playback streams"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "" })

            Item {
                width: parent.width
                height: 42
                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Hardware"
                    color: Theme.text
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: audioPage.hardwareExpanded ? "▾" : "▸"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                           hintingPreference: Font.PreferVerticalHinting }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: audioPage.hardwareExpanded = !audioPage.hardwareExpanded
                }
            }

            Column {
                width: parent.width
                visible: audioPage.hardwareExpanded

                Repeater {
                    model: audioPage.snapshot.cards || []
                    delegate: AudioHardwareRow {
                        required property var modelData
                        width: parent.width
                        card: modelData
                        pending: audioPage.pending
                        busy: Boolean(audioPage.busyTargets[String(modelData.name)])
                        onActionRequested: (action, target, value, fieldKey, generation) =>
                            audioPage.sendAction(action, target, value, fieldKey, generation)
                    }
                }

                Item {
                    visible: (audioPage.snapshot.cards || []).length === 0
                    width: parent.width
                    height: 72
                    Text {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                        verticalAlignment: Text.AlignVCenter
                        text: "No audio cards found"
                        color: Theme.textMuted
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "" })

            Item {
                width: parent.width
                height: 42
                Text {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Automatic Switching"
                    color: Theme.text
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: audioPage.automationExpanded ? "▾" : "▸"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                           hintingPreference: Font.PreferVerticalHinting }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: audioPage.automationExpanded = !audioPage.automationExpanded
                }
            }

            AudioPriorityEditor {
                width: parent.width
                visible: audioPage.automationExpanded
                automation: audioPage.snapshot.automation || ({})
                service: audioPage.snapshot.service || ({})
                sinks: audioPage.snapshot.sinks || []
                onUpdated: next => audioPage.applySnapshot(next)
                onError: message => audioPage.statusMessage = String(message)
            }
        }

        Text {
            visible: audioPage.statusMessage !== "" && !audioPage.initialRetryAvailable
            width: content.width
            text: audioPage.statusMessage
            wrapMode: Text.WordWrap
            color: audioPage.snapshot.stale === true ? Theme.error : Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                   hintingPreference: Font.PreferVerticalHinting }
            leftPadding: 4
        }
    }
}
