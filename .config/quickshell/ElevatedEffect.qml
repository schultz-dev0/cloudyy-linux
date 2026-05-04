// ElevatedEffect.qml
import QtQuick
import QtQuick.Effects

RectangularShadow {
    required property var target

    anchors.fill: target
    visible: target.visible
    z: -1
    radius: target.radius
    blur: 22
    spread: 0
    offset: Qt.vector2d(0, 8)
    color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.28)
    cached: true
}
