// modules/dock/DockUpright.qml
// Undoes Dock.qml's edgeFrame for one piece of content (an icon, a label, the
// drag ghost) so it stays upright on every edge. Same nesting as edgeFrame —
// scale on the inner item, rotation on the outer — needed for the same
// scale-then-rotate composition order (see edgeFrame's comment in Dock.qml).
import QtQuick
import "../.."
import "../../ShellEdges.js" as ShellEdges

Item {
    id: root
    anchors.fill: parent

    readonly property var uprightFrame: ShellEdges.glyphFrame(ShellLayout.dockEdge)
    default property alias content: inner.data

    Item {
        id: outer
        anchors.fill: parent
        rotation: root.uprightFrame.rotation

        Item {
            id: inner
            anchors.fill: parent
            transform: [
                Scale {
                    origin.x: inner.width / 2
                    origin.y: inner.height / 2
                    xScale: root.uprightFrame.xScale
                    yScale: root.uprightFrame.yScale
                }
            ]
        }
    }
}
