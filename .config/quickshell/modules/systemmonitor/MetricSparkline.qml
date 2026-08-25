import QtQuick
import "../.."

Row {
    id: root

    property var values: []
    property int barHeight: 28

    spacing: 1
    height: barHeight
    width: parent ? parent.width : implicitWidth

    Repeater {
        model: root.values.length
        delegate: Rectangle {
            required property int index
            readonly property real norm: root.values[index] / 100.0
            readonly property real h: Math.max(2, norm * root.barHeight)

            width: root.values.length > 0
                ? Math.max(2, (root.width - (root.values.length - 1) * root.spacing) / root.values.length)
                : 2
            height: h
            anchors.bottom: parent.bottom
            radius: 1
            color: norm >= 0.85
                ? Theme.accent
                : norm >= 0.5
                  ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.65)
                  : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32)
        }
    }
}
