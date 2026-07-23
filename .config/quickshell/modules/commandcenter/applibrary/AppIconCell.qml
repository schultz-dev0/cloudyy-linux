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
    signal newInstanceRequested()

    readonly property int iconSize: 48
    readonly property int selectionPad: 3
    readonly property int cellHeight: 88

    width: cellWidth
    height: cellHeight

    function wantsNewInstance(mouse) {
        if (!root.running || !mouse)
            return false;
        if (mouse.button === Qt.MiddleButton)
            return true;
        return ((mouse.modifiers ?? 0) & Qt.ShiftModifier) !== 0;
    }

    Column {
        id: iconCol
        z: 1
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Item {
            id: iconSlot
            width: root.iconSize + root.selectionPad * 2
            height: width
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                anchors.fill: parent
                radius: 10
                visible: root.selected
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                border.width: 1.5
            }

            AppIcon {
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                iconSize: root.iconSize
                appData: root.appData
            }

            Rectangle {
                id: newInstanceBtn
                visible: root.running && cellMouse.containsMouse
                width: 18
                height: 18
                radius: 9
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -2
                anchors.rightMargin: -2
                color: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.95)
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                border.width: 1
                z: 2

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.on_primary_container
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: mouse => {
                        mouse.accepted = true;
                        root.newInstanceRequested();
                    }
                }
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
        id: cellMouse
        z: 0
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (root.wantsNewInstance(mouse))
                root.newInstanceRequested();
            else
                root.activated();
        }
    }
}
