import QtQuick
import ".."
import "AudioState.js" as AudioState

Item {
    id: root

    required property var stream
    required property var sinks
    required property var pending
    property bool busy: false
    signal actionRequested(string action, string target, var value, string fieldKey, int generation)

    implicitHeight: content.implicitHeight
    height: implicitHeight

    function pendingKey(field) {
        return "stream:" + String(root.stream.index) + ":" + field;
    }

    function displayedValue(field, fallback) {
        return AudioState.displayValue(root.pending, root.pendingKey(field), fallback);
    }

    function sinkIndex(name) {
        const choices = root.sinks || [];
        for (let index = 0; index < choices.length; index++) {
            if (String(choices[index].name) === String(name)) return index;
        }
        return -1;
    }

    Column {
        id: content
        width: parent.width

        Item {
            width: parent.width
            height: 52
            Text {
                anchors { left: parent.left; leftMargin: 14; right: media.left; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                text: String(root.stream.app_name || "Playback Stream")
                elide: Text.ElideRight
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                id: media
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.42
                horizontalAlignment: Text.AlignRight
                text: String(root.stream.media_name || "")
                elide: Text.ElideLeft
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        AudioVolumeRow {
            id: volumeRow
            width: parent.width
            label: "Volume"
            targetId: String(root.stream.index)
            targetKind: "stream"
            value: Number(root.displayedValue("volume", root.stream.volume))
            muted: Boolean(root.displayedValue("muted", root.stream.muted))
            busy: root.busy
            onVolumeEdited: (value, generation) => {
                if (volumeRow.editedTargetId === "" || volumeRow.editedTargetKind !== "stream") return;
                root.actionRequested("set_stream_volume", volumeRow.editedTargetId, value,
                    "stream:" + volumeRow.editedTargetId + ":volume", generation);
            }
            onMuteEdited: muted => root.actionRequested(
                "set_stream_mute", String(root.stream.index), muted,
                "stream:" + root.stream.index + ":muted", 0)
        }

        Item {
            width: parent.width
            height: 50
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Output"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudSelect {
                id: sinkSelect
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 250
                compact: true
                options: root.sinks || []
                textRole: "description"
                currentIndex: root.sinkIndex(root.displayedValue("sink_name", root.stream.sink_name))
                enabled: !root.busy && (root.sinks || []).length > 0
                onActivated: index => {
                    if (index < 0 || index >= root.sinks.length) return;
                    root.actionRequested("move_stream", String(root.stream.index), root.sinks[index].name,
                        "stream:" + root.stream.index + ":sink_name", 0);
                }
            }
        }
    }
}
