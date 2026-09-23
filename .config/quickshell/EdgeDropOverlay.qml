// EdgeDropOverlay.qml — drop-zone preview while the bar or dock is being
// dragged to another edge. Click-through: the drag itself stays with the
// pressed bar/dock surface (Wayland keeps delivering its motion events).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: overlay

    screen: ShellLayout.moveScreen ?? Quickshell.screens[0]
    visible: ShellLayout.movingWhich !== "" && ShellLayout.moveScreen !== null
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:edge-drop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    readonly property int band: 6

    component EdgeBand: Rectangle {
        id: edgeBand
        required property string edge
        readonly property bool target: ShellLayout.moveTargetEdge === edge
        readonly property string occupant: ShellLayout.barEdge === edge ? "Bar"
            : (ShellLayout.dockEdge === edge ? "Dock" : "")

        x: edge === "right" ? overlay.width - width : 0
        y: edge === "bottom" ? overlay.height - height : 0
        width: edge === "left" || edge === "right" ? overlay.band : overlay.width
        height: edge === "top" || edge === "bottom" ? overlay.band : overlay.height
        color: target ? Theme.accent : Theme.hairline

        Text {
            visible: edgeBand.occupant !== ""
            text: edgeBand.occupant
            color: edgeBand.target ? Theme.accent : Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            x: edgeBand.edge === "right" ? -width - 8
                : (edgeBand.edge === "left" ? edgeBand.width + 8 : (edgeBand.width - width) / 2)
            y: edgeBand.edge === "bottom" ? -height - 8
                : (edgeBand.edge === "top" ? edgeBand.height + 8 : (edgeBand.height - height) / 2)
        }
    }

    EdgeBand { edge: "top" }
    EdgeBand { edge: "bottom" }
    EdgeBand { edge: "left" }
    EdgeBand { edge: "right" }
}
