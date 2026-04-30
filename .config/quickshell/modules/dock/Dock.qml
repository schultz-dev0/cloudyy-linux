import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dock
    anchors { bottom: true }
    implicitWidth: 300
    implicitHeight: 80
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

    Rectangle {
        anchors.centerIn: parent
        width: 200; height: 60
        radius: 14
        color: "#aa1e1e2e"
        Text {
            anchors.centerIn: parent
            text: "dock stub"
            color: "white"
            font.pixelSize: 12
        }
    }
}
