pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property string label
    required property string imagePath
    required property bool selected
    required property bool isCurrent
    required property int cellWidth
    signal activated()

    readonly property int boxPadding: 14
    readonly property int boxRadius: 16
    readonly property int imageSize: Math.min(root.cellWidth - 36, 148)
    readonly property int slotSize: root.imageSize + root.boxPadding * 2

    width: cellWidth
    height: slotSize

    Item {
        width: root.slotSize
        height: root.slotSize
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: root.boxRadius
            visible: root.selected || root.isCurrent
            color: root.selected
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                : "transparent"
            border.color: root.selected
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            border.width: root.selected ? 1.5 : 1
        }

        Image {
            anchors.centerIn: parent
            width: root.imageSize
            height: root.imageSize
            source: root.imagePath.length > 0 ? "file://" + root.imagePath : ""
            // Never decode a full-resolution wallpaper for a 148px thumbnail.
            sourceSize.width: Math.ceil(root.imageSize * 1.25)
            sourceSize.height: Math.ceil(root.imageSize * 1.25)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 8
            width: currentLabel.width + 8
            height: 16
            radius: 8
            visible: root.isCurrent
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
            z: 1

            Text {
                id: currentLabel
                anchors.centerIn: parent
                text: "current"
                color: Theme.on_primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 8
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}
