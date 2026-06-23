pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property var apps
    required property var isRunningFunc
    signal appActivated(var app)

    readonly property int iconCellWidth: 72
    height: apps.length > 0 ? 100 : 0
    visible: apps.length > 0

    Text {
        id: label
        anchors.left: parent.left
        text: "RECENT"
        color: Theme.on_surface_variant
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    Flickable {
        id: flick
        anchors {
            top: label.bottom
            topMargin: 6
            left: parent.left
            right: parent.right
        }
        height: 84
        contentWidth: row.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row
            height: parent.height
            spacing: 4
            leftPadding: 0
            rightPadding: 0

            Repeater {
                model: root.apps
                delegate: AppIconCell {
                    required property var modelData
                    appData: modelData
                    running: root.isRunningFunc(modelData)
                    cellWidth: root.iconCellWidth
                    onActivated: root.appActivated(modelData)
                }
            }
        }
    }
}
