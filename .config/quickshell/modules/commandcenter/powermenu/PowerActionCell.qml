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

    Rectangle {
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }
        width: 54
        height: 54
        radius: 12
        visible: root.selected
        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
        border.width: 2
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 3

        Item {
            width: 48
            height: 48
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: root.icon
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 26
                color: root.selected ? Theme.primary : Theme.textPrimary
            }
        }

        Text {
            width: root.cellWidth - 6
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: Theme.textPrimary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            lineHeight: 1.1
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
