import QtQuick
import ".."
import "BluetoothState.js" as BluetoothState

Item {
    id: panel

    required property var device
    required property var pending
    required property var busyTargets
    signal actionRequested(string action, string target, var value, string fieldKey, int generation)

    implicitHeight: content.implicitHeight
    height: implicitHeight

    readonly property bool busy: device
        ? Boolean(busyTargets[String(device.address)])
        : false

    function pendingKey(field) {
        if (!panel.device)
            return "";
        return "device:" + String(panel.device.address) + ":" + field;
    }

    function trustedValue() {
        if (!panel.device)
            return false;
        return Boolean(BluetoothState.displayValue(
            panel.pending, pendingKey("trusted"), panel.device.trusted));
    }

    function request(action, value, field) {
        if (!panel.device)
            return;
        panel.actionRequested(
            action,
            String(panel.device.address),
            value,
            pendingKey(field),
            0
        );
    }

    Column {
        id: content
        width: parent.width
        spacing: 0

        Item {
            visible: panel.device === null || panel.device === undefined
            width: parent.width
            height: 100
            Text {
                anchors {
                    fill: parent
                    margins: 16
                }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: "Select a device for details. Double-click to connect or disconnect. Right-click or press Enter for Connect / Remove."
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 11
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
        }

        Column {
            visible: panel.device !== null && panel.device !== undefined
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 64
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        top: parent.top
                        topMargin: 12
                        right: parent.right
                        rightMargin: 10
                    }
                    text: panel.device
                        ? String(panel.device.display_name || panel.device.name
                            || panel.device.address || "")
                        : ""
                    elide: Text.ElideRight
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 14
                        weight: Font.Medium
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        bottom: parent.bottom
                        bottomMargin: 10
                        right: parent.right
                        rightMargin: 10
                    }
                    text: panel.device ? String(panel.device.address || "") : ""
                    elide: Text.ElideRight
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
            }

            Rectangle {
                visible: Boolean(panel.device && panel.device.paired)
                width: parent.width - 20
                x: 10
                height: 1
                color: Theme.glass(Theme.outline_variant, 0.35)
            }

            Item {
                visible: Boolean(panel.device && panel.device.paired)
                width: parent.width
                height: 48
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Auto-connect"
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 12
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                CloudSwitch {
                    id: trustSwitch
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    checked: panel.trustedValue()
                    enabled: !panel.busy
                    onToggled: checked => {
                        trustSwitch.checked = Qt.binding(function() {
                            return panel.trustedValue();
                        });
                        panel.request("trust", checked, "trusted");
                    }
                }
            }
        }
    }
}
