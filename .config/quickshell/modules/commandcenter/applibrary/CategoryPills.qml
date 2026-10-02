pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

// Wrapping pill row (was a horizontal Flickable that clipped categories off
// the right edge — Productivity/Utilities were unreachable). Square, rule §4.
Item {
    id: root

    required property var labels
    required property string activeLabel
    property int keyboardFocusIndex: -1
    signal categorySelected(string label)

    implicitHeight: flow.implicitHeight + 8
    height: implicitHeight

    Flow {
        id: flow
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
        leftPadding: 14
        rightPadding: 14
        spacing: 6

        Repeater {
            model: root.labels
            delegate: Rectangle {
                id: pill
                required property string modelData
                required property int index
                height: 28
                width: pillText.width + 24
                radius: 2
                readonly property bool isActive: modelData === root.activeLabel
                readonly property bool isKeyboardFocused: root.keyboardFocusIndex === index
                color: isActive ? Theme.accentMuted : Theme.surfaceOverlay
                border.color: isKeyboardFocused
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                    : (isActive
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                        : "transparent")
                border.width: isKeyboardFocused || isActive ? 1.5 : 0

                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: modelData
                    // Active sits on the accentMuted fill, where accent
                    // itself is ~1-3:1 in every theme; onAccent is 3-10:1.
                    color: isActive ? Theme.accentText
                        : isKeyboardFocused ? Theme.accent : Theme.textMuted
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
