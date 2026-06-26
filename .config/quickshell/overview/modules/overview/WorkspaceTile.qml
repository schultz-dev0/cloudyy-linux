pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../../"

Item {
    id: root

    required property int workspaceId
    required property var windows
    required property bool active
    required property bool selected
    required property bool overviewActive
    required property var toplevelByAddress
    required property bool tileCaptureActive
    property var monitorData: null
    property int tileWidth: 280
    property int tileHeight: 180

    signal requestWorkspace(int workspaceId)
    signal requestFocusWindow(var windowData)
    signal requestCloseWindow(var windowData)
    signal peekRequested()
    signal peekDismissed()

    readonly property int labelStripHeight: 22
    readonly property int previewHeight: root.height - labelStripHeight
    readonly property int cornerRadius: 16
    readonly property int previewRadius: 10
    readonly property int previewInset: 8

    width: tileWidth
    height: tileHeight

    RectangularShadow {
        anchors.fill: tile
        radius: root.cornerRadius
        blur: 40
        spread: 2
        offset: Qt.vector2d(0, 5)
        color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.12)
        cached: true
        z: -1
    }

    Rectangle {
        id: tile

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.selected
            ? Qt.tint(Theme.glassSection, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
            : root.active
                ? Theme.glassSectionHigh
                : Theme.glassSection
        border.color: root.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            : root.active
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.22)
        border.width: 1
        antialiasing: true
        clip: true

        Behavior on color {
            enabled: Perf.animationsEnabled
            ColorAnimation { duration: Perf.msHalf(140) }
        }

        Behavior on border.color {
            enabled: Perf.animationsEnabled
            ColorAnimation { duration: Perf.msHalf(140) }
        }

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: root.previewHeight

                WorkspacePreview {
                    anchors.fill: parent
                    anchors.margins: root.previewInset
                    cornerRadius: root.previewRadius
                    windows: root.windows ?? []
                    monitorData: root.monitorData
                    toplevelByAddress: root.toplevelByAddress
                    overviewActive: root.overviewActive
                    tileCaptureActive: root.tileCaptureActive
                }
            }

            Rectangle {
                width: parent.width
                height: root.labelStripHeight
                radius: root.cornerRadius
                color: Theme.glassSectionHigh

                // Square off the top so only bottom corners stay rounded with the tile.
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: root.cornerRadius
                    color: parent.color
                }

                Text {
                    anchors.centerIn: parent
                    text: "WORKSPACE " + root.workspaceId
                    color: root.active ? Theme.primary : Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    Timer {
        id: peekShowTimer

        interval: 150
        repeat: false
        onTriggered: root.peekRequested()
    }

    MouseArea {
        id: tileMouseArea

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onEntered: peekShowTimer.restart()
        onExited: {
            peekShowTimer.stop();
            root.peekDismissed();
        }
        onClicked: root.requestWorkspace(root.workspaceId)
    }
}
