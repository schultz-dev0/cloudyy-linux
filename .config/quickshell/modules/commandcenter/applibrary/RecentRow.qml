pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property var apps
    required property var isRunningFunc
    property int keyboardFocusIndex: -1
    signal appActivated(var app)
    signal appNewInstance(var app)

    readonly property int iconCellWidth: 72
    readonly property int cellSpacing: 4
    readonly property int rowHeight: 88
    height: apps.length > 0 ? label.height + 6 + rowHeight : 0
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
        height: root.rowHeight
        contentWidth: row.width
        clip: false
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: row
            height: parent.height
            spacing: root.cellSpacing
            leftPadding: 0
            rightPadding: 0

            Repeater {
                model: root.apps
                delegate: AppIconCell {
                    required property var modelData
                    required property int index
                    appData: modelData
                    running: root.isRunningFunc(modelData)
                    cellWidth: root.iconCellWidth
                    selected: root.keyboardFocusIndex === index
                    onActivated: root.appActivated(modelData)
                    onNewInstanceRequested: root.appNewInstance(modelData)
                }
            }
        }
    }

    function ensureIndexVisible(index) {
        if (index < 0 || index >= apps.length)
            return;
        const cellStep = iconCellWidth + cellSpacing;
        const cellLeft = index * cellStep;
        const cellRight = cellLeft + iconCellWidth;
        const viewLeft = flick.contentX;
        const viewRight = viewLeft + flick.width;
        if (cellLeft < viewLeft)
            flick.contentX = cellLeft;
        else if (cellRight > viewRight)
            flick.contentX = Math.max(0, cellRight - flick.width);
    }
}
