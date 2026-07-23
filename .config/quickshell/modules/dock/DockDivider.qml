import QtQuick
import "../.."

Item {
    required property real iconSize
    property real maxScale: 1.0

    implicitWidth: 1
    implicitHeight: iconSize * maxScale + 6

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6 + iconSize * 0.225
        width: 1
        height: iconSize * 0.55
        radius: 0.5
        color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.45)
    }
}
