import QtQuick

// Top-attached island silhouette: square top corners (flush with the screen
// edge) and rounded bottom corners. A plain Rectangle with per-corner radius
// (Qt 6.7+) replaces the old custom Shape/ShapePath geometry it used to take
// to get independent top/bottom radii — cheaper to resize/animate (native
// rect, no path retessellation every frame) and far simpler.
Rectangle {
    id: root

    property real shoulderRadius: 10
    property real lowerRadius: 26
    property real strokeWidth: 1
    property color strokeColor: Qt.rgba(1, 1, 1, 0.10)
    property color fillColor: Qt.rgba(0, 0, 0, 0.97)

    readonly property real shoulder: Math.min(shoulderRadius, width / 4, height)
    readonly property real lower: Math.min(lowerRadius, height / 2, width / 2)

    antialiasing: true
    color: root.fillColor
    border.width: root.strokeWidth
    border.color: root.strokeColor
    topLeftRadius: root.shoulder
    topRightRadius: root.shoulder
    bottomLeftRadius: root.lower
    bottomRightRadius: root.lower
}
