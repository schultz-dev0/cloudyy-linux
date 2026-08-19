import QtQuick

// Tileable dot-grid texture for the "Dots" material — small interactive
// controls (buttons, toggles) and the island's subtle fill. Tinted at
// runtime via a templated SVG data URI instead of a Canvas repaint: the
// tile is a couple of pixels, GPU-cached like any other Image, and never
// needs to redraw itself.
Image {
    id: root

    required property color tint
    property real dotAlpha: 0.5
    property int cell: 6
    property real dotRadius: 1

    fillMode: Image.Tile
    smooth: false
    asynchronous: false
    cache: false

    readonly property string _rgba: Math.round(tint.r * 255) + "," + Math.round(tint.g * 255)
        + "," + Math.round(tint.b * 255) + "," + dotAlpha

    source: "data:image/svg+xml," + encodeURIComponent(
        "<svg xmlns='http://www.w3.org/2000/svg' width='" + cell + "' height='" + cell + "'>"
        + "<circle cx='" + (cell / 2) + "' cy='" + (cell / 2) + "' r='" + dotRadius
        + "' fill='rgba(" + _rgba + ")'/></svg>"
    )
}
