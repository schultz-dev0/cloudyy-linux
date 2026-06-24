pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property string icon
    required property string label
    required property bool selected
    required property int cellWidth
    signal activated()

    width: cellWidth
    height: 80

    Column {
        id: iconCol
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 2

        Item {
            id: iconSlot
            width: 48
            height: 48
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 50
                height: 50
                radius: 10
                visible: root.selected
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                border.width: 1.5
            }

            Text {
                anchors.centerIn: parent
                text: root.icon
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 26
                color: root.selected ? Theme.primary : Theme.textPrimary
            }
        }

        Text {
            width: root.cellWidth - 8
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: Theme.textPrimary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            lineHeight: 1.2
            lineHeightMode: Text.ProportionalHeight
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
