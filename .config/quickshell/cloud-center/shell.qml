//@ pragma UseQApplication
import QtQuick
import Quickshell
import "."   // shared Theme.qml singleton (matugen-generated); symlinked into this dir since
             // Quickshell's per-config import sandbox does not resolve ".." across config roots

FloatingWindow {
    id: root
    title: "Cloud Center"
    implicitWidth: 1100
    implicitHeight: 760
    color: "transparent"

    property string currentPageId: ""
    readonly property int sidebarStripWidth: 240

    // Near-transparent glass strip; Hyprland blurs the desktop behind it.
    Rectangle {
        id: glassStrip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: root.sidebarStripWidth
        color: Theme.glass(Theme.surface_container, 0.30)
    }

    // Opaque content pane.
    Rectangle {
        id: contentPane
        anchors { left: glassStrip.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        color: Theme.background

        Item { id: contentArea; anchors.fill: parent }
    }
}
