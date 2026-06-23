pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."

// PopupWindow renders outside the bar layer (bar PanelWindow clips anything below barBg).
PopupWindow {
    id: tip

    required property Item anchorItem
    property bool hovered: false

    readonly property var bat: BatteryService

    visible: tip.hovered && bat.available
    color: "transparent"
    readonly property real tipWidth: Math.max(200, col.implicitWidth + 20)
    readonly property real tipHeight: col.implicitHeight + 20
    implicitWidth: tipWidth
    implicitHeight: tipHeight

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip

    readonly property int centerNudgeX: 38

    function syncAnchor() {
        if (!anchorItem)
            return;
        const w = tip.tipWidth;
        tip.anchor.rect.x = anchorItem.width / 2 - w / 2 + centerNudgeX;
        tip.anchor.rect.y = anchorItem.height;
        tip.anchor.rect.w = 1;
        tip.anchor.rect.h = 1;
        tip.anchor.updateAnchor();
    }

    onVisibleChanged: if (visible)
        syncAnchor()

    onTipWidthChanged: if (visible)
        syncAnchor()

    Connections {
        target: anchorItem
        function onXChanged() {
            if (tip.visible)
                tip.syncAnchor();
        }
        function onYChanged() {
            if (tip.visible)
                tip.syncAnchor();
        }
        function onWidthChanged() {
            if (tip.visible)
                tip.syncAnchor();
        }
    }

    Rectangle {
        id: tipBody
        anchors.fill: parent
        radius: 12
        color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.96)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
        border.width: 1

        ColumnLayout {
            id: col
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 6

            Text {
                text: "󰁹  " + Math.round(bat.percent) + "% · " + bat.statusLabel
                color: Theme.on_surface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.weight: Font.Bold
                Layout.fillWidth: true
            }

            Text {
                text: bat.rateEtaLabel
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                Layout.fillWidth: true
            }
        }
    }
}
