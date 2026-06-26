pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../../../"

Item {
    id: root

    required property var anchorItem
    required property int workspaceId
    required property var windows
    required property var monitorData
    required property var toplevelByAddress
    required property bool overviewActive
    required property bool active
    required property bool selected
    required property int outerMargin

    signal requestFocusWindow(var windowData)
    signal peekEntered()
    signal peekExited()

    readonly property int labelStripHeight: 22
    readonly property int previewInset: 8
    readonly property int cornerRadius: 16
    readonly property int previewRadius: 10
    readonly property int gap: 10
    readonly property real peekScale: 2.2

    readonly property real anchorX: anchorItem ? anchorItem.mapToItem(root.parent, 0, 0).x : 0
    readonly property real anchorY: anchorItem ? anchorItem.mapToItem(root.parent, 0, 0).y : 0
    readonly property real anchorW: anchorItem ? anchorItem.width : 0
    readonly property real anchorH: anchorItem ? anchorItem.height : 0

    readonly property int peekWidth: {
        if (!anchorItem)
            return 0;
        const maxW = root.parent.width - outerMargin * 2;
        return Math.min(Math.round(anchorW * peekScale), maxW);
    }

    readonly property int peekHeight: {
        if (!anchorItem)
            return 0;
        const previewH = anchorH - labelStripHeight;
        const maxH = root.parent.height - outerMargin * 2;
        return Math.min(Math.round(previewH * peekScale) + labelStripHeight, maxH);
    }

    readonly property bool placeBelow: {
        const aboveY = anchorY - peekHeight - gap;
        return aboveY < outerMargin;
    }

    readonly property real posX: {
        let x = anchorX + (anchorW - peekWidth) / 2;
        x = Math.max(outerMargin, x);
        x = Math.min(x, root.parent.width - peekWidth - outerMargin);
        return x;
    }

    readonly property real posY: placeBelow
        ? anchorY + anchorH + gap
        : anchorY - peekHeight - gap

    visible: anchorItem !== null && peekWidth > 0 && peekHeight > 0
    x: posX
    y: posY
    width: peekWidth
    height: peekHeight
    z: 100

    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.92
    transformOrigin: placeBelow ? Item.Top : Item.Bottom

    Behavior on opacity {
        enabled: Perf.animationsEnabled
        NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
    }

    Behavior on scale {
        enabled: Perf.animationsEnabled
        NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
    }

    RectangularShadow {
        anchors.fill: card
        radius: root.cornerRadius
        blur: 48
        spread: 2
        offset: Qt.vector2d(0, 6)
        color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.18)
        cached: true
        z: -1
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: root.cornerRadius
        color: root.selected
            ? Qt.tint(Theme.glassSection, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
            : root.active
                ? Theme.glassSectionHigh
                : Theme.glassSection
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
        border.width: 1
        antialiasing: true
        clip: true

        Column {
            anchors.fill: parent
            spacing: 0

            Item {
                width: parent.width
                height: root.height - root.labelStripHeight

                WorkspacePreview {
                    anchors.fill: parent
                    anchors.margins: root.previewInset
                    cornerRadius: root.previewRadius
                    windows: root.windows ?? []
                    monitorData: root.monitorData
                    toplevelByAddress: root.toplevelByAddress
                    overviewActive: root.overviewActive
                    tileCaptureActive: true
                    snapshotOnly: true
                    interactive: true
                    onRequestFocusWindow: windowData => root.requestFocusWindow(windowData)
                }
            }

            Rectangle {
                width: parent.width
                height: root.labelStripHeight
                radius: root.cornerRadius
                color: Theme.glassSectionHigh

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

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: root.peekEntered()
        onExited: root.peekExited()
    }
}
