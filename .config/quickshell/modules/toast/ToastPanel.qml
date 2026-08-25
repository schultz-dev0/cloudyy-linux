pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as QuickToast

PanelWindow {
    id: root

    readonly property var toasts: QuickToast.ToastQueueService.activeToasts
    readonly property bool panelActive: toasts.length > 0

    anchors { top: true; right: true }
    margins { top: 16; right: 16 }
    implicitWidth: panelActive ? 320 : 0
    implicitHeight: panelActive ? column.implicitHeight : 0
    visible: panelActive
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            model: root.toasts
            delegate: QuickToast.ToastCard {
                required property var modelData
                toast: modelData
            }
        }
    }
}
