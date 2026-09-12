import QtQuick

// Static tiled film grain. Last-on-top via z; Image does not take clicks.
// Asset path lives on Theme so Cloud Center's symlink of this file still
// resolves to the main-shell PNG.
Image {
    anchors.fill: parent
    z: 1000
    enabled: false
    fillMode: Image.Tile
    smooth: false
    asynchronous: false
    source: Theme.grainTexture
    opacity: Theme.grainOpacity
}
