import QtQuick
import ".."
import "AudioState.js" as AudioState

Item {
    id: panel

    required property string kind
    required property var devices
    required property string selectedId
    required property var pending
    required property var busyTargets
    signal selected(string id)
    signal actionRequested(string action, string target, var value, string fieldKey, int generation)

    implicitHeight: content.implicitHeight
    height: implicitHeight

    readonly property var selectedDevice: deviceFor(selectedId)
    readonly property string displayKind: kind === "sink" ? "Output" : "Input"

    function deviceFor(name) {
        const list = devices || [];
        for (let index = 0; index < list.length; index++) {
            if (String(list[index].name) === String(name))
                return list[index];
        }
        return null;
    }

    function pendingKeyFor(deviceKind, target, field) {
        return deviceKind + ":" + String(target) + ":" + field;
    }

    function pendingKey(device, field) {
        return pendingKeyFor(kind, device.name, field);
    }

    function actionForKind(deviceKind, field) {
        if (deviceKind === "sink") {
            if (field === "volume") return "set_sink_volume";
            if (field === "mute") return "set_sink_mute";
            if (field === "default") return "set_default_sink";
            return "set_sink_port";
        }
        if (field === "volume") return "set_source_volume";
        if (field === "mute") return "set_source_mute";
        if (field === "default") return "set_default_source";
        return "set_source_port";
    }

    function actionFor(field) {
        return actionForKind(kind, field);
    }

    function activePort(device) {
        if (!device) return "";
        return String(AudioState.displayValue(
            pending, pendingKey(device, "port"), device.active_port));
    }

    function isDefault(device) {
        if (!device) return false;
        return Boolean(AudioState.displayValue(
            pending, pendingKey(device, "default"), device.is_default));
    }

    function portIndex(device) {
        if (!device || !device.ports) return -1;
        return device.ports.findIndex(port => String(port.name) === activePort(device));
    }

    function friendlyState(state) {
        switch (String(state || "").toUpperCase()) {
        case "RUNNING":
            return "In use";
        case "IDLE":
            return "Idle";
        case "SUSPENDED":
            return "Not in use";
        case "INIT":
            return "Starting";
        case "":
            return "Unknown";
        default:
            return String(state);
        }
    }

    function deviceStatus(device) {
        if (isDefault(device)) return "Default";
        if (device.muted) return "Muted";
        return friendlyState(device.state || "Idle");
    }

    function bluetoothMetadata(device) {
        const properties = device && device.properties ? device.properties : {};
        const codec = properties["bluez5.codec"] || properties["bluetooth.codec"] || "";
        const profile = properties["bluez5.profile"] || properties["device.profile"] || "";
        const parts = [];
        if (codec) parts.push("Codec " + codec);
        if (profile) parts.push("Profile " + profile);
        return parts.join(" · ");
    }

    Column {
        id: content
        width: parent.width

        Repeater {
            model: panel.devices || []
            delegate: SelectableRow {
                id: deviceRow
                required property var modelData
                required property int index
                width: content.width
                title: String(modelData.description || modelData.name || "Device")
                subtitle: String(modelData.type || "Audio") + " · "
                    + panel.deviceStatus(modelData)
                selected: String(modelData.name) === panel.selectedId
                showDivider: index < (panel.devices ? panel.devices.length : 0) - 1
                dividerInset: 14
                leadingGlyph: ""
                onClicked: {
                    const name = String(deviceRow.modelData.name);
                    panel.selected(name);
                    if (!panel.isDefault(deviceRow.modelData)
                        && !panel.busyTargets[name]) {
                        panel.actionRequested(panel.actionFor("default"), name, true,
                            panel.pendingKey(deviceRow.modelData, "default"), 0);
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hairline
            visible: panel.selectedDevice !== null
        }

        AudioVolumeRow {
            id: volumeRow
            visible: panel.selectedDevice !== null
            width: parent.width
            label: panel.displayKind + " volume"
            targetId: panel.selectedDevice ? String(panel.selectedDevice.name) : ""
            targetKind: panel.kind
            value: panel.selectedDevice ? Number(AudioState.displayValue(
                panel.pending, panel.pendingKey(panel.selectedDevice, "volume"), panel.selectedDevice.volume)) : 0
            muted: panel.selectedDevice ? Boolean(AudioState.displayValue(
                panel.pending, panel.pendingKey(panel.selectedDevice, "mute"), panel.selectedDevice.muted)) : false
            busy: panel.selectedDevice ? Boolean(panel.busyTargets[String(panel.selectedDevice.name)]) : false
            onVolumeEdited: (value, generation) => {
                if (volumeRow.editedTargetId === "" || volumeRow.editedTargetKind === "") return;
                panel.actionRequested(panel.actionForKind(volumeRow.editedTargetKind, "volume"),
                    volumeRow.editedTargetId, value,
                    panel.pendingKeyFor(volumeRow.editedTargetKind, volumeRow.editedTargetId, "volume"),
                    generation);
            }
            onMuteEdited: muted => {
                if (!panel.selectedDevice) return;
                panel.actionRequested(panel.actionFor("mute"), String(panel.selectedDevice.name), muted,
                    panel.pendingKey(panel.selectedDevice, "mute"), 0);
            }
        }

        Item {
            visible: panel.selectedDevice !== null && panel.selectedDevice.ports
                && panel.selectedDevice.ports.length > 1
            width: parent.width
            height: 50
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Port"
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudSelect {
                id: portSelect
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 220
                compact: true
                options: panel.selectedDevice ? panel.selectedDevice.ports : []
                textRole: "description"
                currentIndex: panel.portIndex(panel.selectedDevice)
                enabled: panel.selectedDevice && !panel.busyTargets[String(panel.selectedDevice.name)]
                onActivated: index => {
                    if (!panel.selectedDevice || index < 0) return;
                    const port = panel.selectedDevice.ports[index];
                    panel.actionRequested(panel.actionFor("port"), String(panel.selectedDevice.name), String(port.name),
                        panel.pendingKey(panel.selectedDevice, "port"), 0);
                }
            }
        }

        Item {
            visible: panel.selectedDevice !== null
            width: parent.width
            height: 40
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Audio format"
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.60
                horizontalAlignment: Text.AlignRight
                text: panel.selectedDevice ? String(panel.selectedDevice.sample_spec || "Unavailable") : ""
                elide: Text.ElideLeft
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Item {
            visible: panel.selectedDevice !== null
            width: parent.width
            height: 40
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "State"
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.60
                horizontalAlignment: Text.AlignRight
                text: panel.selectedDevice ? panel.friendlyState(panel.selectedDevice.state) : ""
                elide: Text.ElideLeft
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Item {
            visible: panel.kind === "sink" && panel.selectedDevice !== null
                && panel.bluetoothMetadata(panel.selectedDevice) !== ""
            width: parent.width
            height: 40
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Bluetooth"
                color: Theme.text
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.60
                horizontalAlignment: Text.AlignRight
                text: panel.bluetoothMetadata(panel.selectedDevice)
                elide: Text.ElideLeft
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }
    }
}
