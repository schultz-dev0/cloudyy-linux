pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../.."
import "../../../overview/services"

Item {
    id: root

    required property var appData
    required property bool running
    required property int cellWidth
    property bool selected: false
    signal activated()

    width: cellWidth
    height: 84

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

            AppIcon {
                anchors.centerIn: parent
                width: 48
                height: 48
                iconSize: 48
                appData: root.appData
            }
        }

        Text {
            width: root.cellWidth - 8
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.appData?.name ?? ""
            color: Theme.textPrimary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            lineHeight: 1.2
            lineHeightMode: Text.ProportionalHeight
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: 4
            height: 4
            radius: 2
            visible: root.running
            color: Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
