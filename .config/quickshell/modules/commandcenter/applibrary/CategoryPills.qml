pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property var labels
    required property string activeLabel
    property int keyboardFocusIndex: -1
    signal categorySelected(string label)

    height: 36

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: row.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function ensurePillVisible(idx) {
            for (let i = 0; i < row.children.length; i++) {
                const pill = row.children[i];
                if (pill.index !== idx)
                    continue;
                const left = pill.x;
                const right = pill.x + pill.width;
                if (left < flick.contentX)
                    flick.contentX = left;
                else if (right > flick.contentX + flick.width)
                    flick.contentX = right - flick.width;
                break;
            }
        }

        Row {
            id: row
            height: parent.height
            spacing: 6
            leftPadding: 0
            rightPadding: 0

            Repeater {
                model: root.labels
                delegate: Rectangle {
                    id: pill
                    required property string modelData
                    required property int index
                    height: 28
                    width: pillText.width + 20
                    radius: 14
                    readonly property bool isActive: modelData === root.activeLabel
                    readonly property bool isKeyboardFocused: root.keyboardFocusIndex === index
                    color: isActive
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                        : Qt.rgba(Theme.surface_variant.r, Theme.surface_variant.g, Theme.surface_variant.b, 0.25)
                    border.color: isKeyboardFocused
                        ? Theme.primary
                        : (isActive
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
                            : "transparent")
                    border.width: isKeyboardFocused ? 2 : 1
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        text: modelData
                        color: isActive || isKeyboardFocused ? Theme.primary : Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.categorySelected(modelData)
                    }
                }
            }
        }
    }

    onKeyboardFocusIndexChanged: flick.ensurePillVisible(keyboardFocusIndex)
}
