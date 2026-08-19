import QtQuick
import QtQuick.Controls
import ".."

Rectangle {
    id: row
    required property string title
    property string description: ""
    property string origin: ""
    property bool editable: true
    property bool canMoveUp: false
    property bool canMoveDown: false

    signal editRequested()
    signal removeRequested()
    signal moveUpRequested()
    signal moveDownRequested()
    signal reorderByRequested(int offset)

    width: parent ? parent.width : 680
    height: 58
    color: "transparent"

    Row {
        anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: row.editable ? "\u{f0493}" : "\u{f033e}"
            color: row.editable ? Theme.accent : Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 14
                   hintingPreference: Font.PreferVerticalHinting }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actions.width - 38
            spacing: 2
            Text {
                width: parent.width
                text: row.title
                elide: Text.ElideRight
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                width: parent.width
                text: row.description
                elide: Text.ElideRight
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Row {
            id: actions
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                id: dragGrip
                visible: row.editable
                width: 24
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "\u{f01db}"
                color: dragHandler.active ? Theme.accent : Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13
                       hintingPreference: Font.PreferVerticalHinting }
                ToolTip.visible: gripHover.hovered
                ToolTip.text: "Drag to reorder"
                HoverHandler { id: gripHover }
                DragHandler {
                    id: dragHandler
                    target: null
                    xAxis.enabled: false
                    onActiveChanged: {
                        if (!active) {
                            const steps = Math.round(translation.y / row.height);
                            if (steps !== 0) row.reorderByRequested(steps);
                        }
                    }
                }
            }
            Text {
                visible: !row.editable
                anchors.verticalCenter: parent.verticalCenter
                text: row.origin === "distro" ? "system" : "manual"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
                rightPadding: 6
            }
            Repeater {
                model: row.editable ? [
                    { glyph: "\u{f0141}", enabled: row.canMoveUp, action: "up" },
                    { glyph: "\u{f0140}", enabled: row.canMoveDown, action: "down" },
                    { glyph: "\u{f03eb}", enabled: true, action: "edit" },
                    { glyph: "\u{f0a79}", enabled: true, action: "remove" },
                ] : []
                delegate: Rectangle {
                    required property var modelData
                    width: 26; height: 26; radius: 2
                    opacity: modelData.enabled ? 1 : 0.28
                    color: actionHover.hovered && modelData.enabled
                        ? Theme.glass(modelData.action === "remove" ? Theme.error : Theme.primary, 0.15)
                        : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.glyph
                        color: modelData.action === "remove" ? Theme.error : Theme.accent
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    HoverHandler { id: actionHover }
                    TapHandler {
                        enabled: modelData.enabled
                        onTapped: {
                            if (modelData.action === "up") row.moveUpRequested();
                            else if (modelData.action === "down") row.moveDownRequested();
                            else if (modelData.action === "edit") row.editRequested();
                            else row.removeRequested();
                        }
                    }
                }
            }
        }
    }
}
