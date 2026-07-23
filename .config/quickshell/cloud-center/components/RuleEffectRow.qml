import QtQuick
import ".."

Rectangle {
    id: row

    required property var field
    property string description: field.description ?? ""
    property bool active: false
    property string value: ""
    property bool last: false
    signal toggled(bool active)
    signal valueEdited(string value)

    width: parent ? parent.width : 680
    height: 58
    color: rowHover.hovered ? Theme.glass(Theme.primary, 0.045) : "transparent"

    function choiceOptions() {
        if (field.type === "bool") return ["On", "Off"];
        return field.choices ?? [];
    }

    Row {
        anchors { fill: parent; leftMargin: 13; rightMargin: 13 }
        spacing: 10

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 9
            color: row.active ? Theme.glass(Theme.primary, 0.14)
                : Theme.glass(Theme.surface_container_high, 0.72)
            Text {
                anchors.centerIn: parent
                text: row.field.type === "bool" ? "\u{f0493}"
                    : row.field.type === "choice" ? "\u{f035e}" : "\u{f044c}"
                color: row.active ? Theme.accent : Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - valueControl.width - activeSwitch.width - 66
            spacing: 2
            Text {
                width: parent.width
                text: row.field.label
                elide: Text.ElideRight
                color: row.active ? Theme.textPrimary : Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                width: parent.width
                text: row.description || (row.active ? "Configured" : "Leave unchanged")
                elide: Text.ElideRight
                color: Theme.textMuted
                opacity: 0.78
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Item {
            id: valueControl
            anchors.verticalCenter: parent.verticalCenter
            width: row.field.type === "bool" ? 88 : 190
            height: 30

            CloudSelect {
                anchors.fill: parent
                visible: row.field.type === "bool" || row.field.type === "choice"
                enabled: row.active
                compact: true
                options: row.choiceOptions()
                currentIndex: row.field.type === "bool"
                    ? (row.value === "off" ? 1 : 0)
                    : Math.max(0, options.indexOf(row.value))
                onActivated: index => row.valueEdited(
                    row.field.type === "bool" ? (index === 0 ? "on" : "off") : options[index])
            }
            CloudTextField {
                anchors.fill: parent
                visible: row.field.type !== "bool" && row.field.type !== "choice"
                enabled: row.active
                compact: true
                text: row.value
                placeholderText: row.active ? "Enter value" : "Not set"
                onTextEdited: value => row.valueEdited(value)
            }
        }

        CloudSwitch {
            id: activeSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: row.active
            onToggled: checked => row.toggled(checked)
        }
    }

    Rectangle {
        visible: !row.last
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 51 }
        height: 1
        color: Theme.glass(Theme.outline_variant, 0.34)
    }
    HoverHandler { id: rowHover }
}
