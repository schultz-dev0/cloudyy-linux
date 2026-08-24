pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickShelf

PanelWindow {
    id: root

    readonly property var captures: QuickShelf.PreviewShelfService.pendingCaptures
    readonly property bool panelActive: captures.length > 0

    anchors { bottom: true; right: true }
    margins { bottom: 16; right: 16 }
    implicitWidth: panelActive ? 200 : 0
    implicitHeight: panelActive ? column.implicitHeight : 0
    visible: panelActive
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:shelf"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    // Bottom-anchored: newest card stays closest to the screen edge it grows
    // from, so the stack builds upward — "clear all" sits at the bottom, under
    // the cards, mirroring how the top-anchored layout used to read top-to-bottom.
    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: root.captures
            delegate: QuickShelf.PreviewCard {
                required property var modelData
                capture: modelData
                onDismissRequested: id => QuickShelf.PreviewShelfService.dismiss(id)
            }
        }

        Text {
            visible: root.captures.length > 1
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: "clear all"
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10

            MouseArea {
                anchors.fill: parent
                onClicked: QuickShelf.PreviewShelfService.dismissAll()
            }
        }
    }
}
