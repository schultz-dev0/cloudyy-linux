import QtQuick
import QtQuick.Effects
import "../services" as S
import ".."

Column {
    id: wallGrid
    // Column has no other width source (unlike RowBase, nothing here binds to
    // parent.width by default) — without this it silently self-sizes from the
    // GridView's implicit width instead of the page's actual available width.
    width: parent ? parent.width : 0
    required property var item
    property string current: item.current ?? ""
    property string previous: ""   // revert target if the apply fails
    property var wallpapers: item.wallpapers ?? []   // mutable copy — item itself is a static snapshot
    // item.thumbnail_size only decides how many columns fit; the tiles
    // themselves grow to fill the row exactly instead of leaving a fixed
    // small size with slack space around them.
    property int contentWidth: width - leftPadding - rightPadding
    property int columns: Math.max(1, Math.floor(contentWidth / ((item.thumbnail_size ?? 132) + 10)))
    property int thumb: Math.floor(contentWidth / columns) - 10
    property int thumbH: Math.round(thumb * 0.636)
    // Matches RowBase's row edge margins so this card's content doesn't sit
    // flush against the card border. Bottom/top matter too, not just left/
    // right — without them the last row's tile borders get visually clipped
    // by the card's own rounded corners.
    padding: 14

    Connections {
        target: S.Backend
        function onActionDone(itemId, ok) {
            if (itemId === wallGrid.item.id && !ok)
                wallGrid.current = wallGrid.previous;
        }
        // Subscribed pages poll theme_mode() backend-side (state.py's
        // wallpaper watcher) and re-send this list whenever it flips, so
        // switching light/dark elsewhere while this page is open refreshes
        // the grid instead of leaving it showing the previous mode's pool.
        function onWallpapersEvent(itemId, wallpapers) {
            if (itemId === wallGrid.item.id) wallGrid.wallpapers = wallpapers;
        }
    }

    // Plain Item, not a positioner, so the GridView inside can use anchors to
    // center itself — Column (wallGrid) is a positioner and forbids anchors
    // on its direct children.
    Item {
        id: gridWrap
        width: wallGrid.contentWidth
        height: grid.height

        // GridView (not Grid+Repeater): columns follow available width
        // instead of the model's fixed count, and delegates outside the
        // viewport are never instantiated, so only the visible rows decode
        // images instead of all of them at once. Backend hands each entry as
        // {path, thumb}: `path` is the real wallpaper file (identity + what
        // actually gets applied), `thumb` is a disk-cached downscaled copy so
        // Qt never decodes a multi-MB source.
        GridView {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            width: wallGrid.columns * cellWidth   // only the used width, so it centers instead of left-packing
            height: Math.min(4, Math.ceil(model.length / wallGrid.columns)) * cellHeight
            cellWidth: wallGrid.thumb + 10
            cellHeight: wallGrid.thumbH + 10
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: wallGrid.wallpapers
            delegate: Rectangle {
                required property var modelData
                width: wallGrid.thumb; height: wallGrid.thumbH; radius: 10
                border.width: wallGrid.current === modelData.path ? 2 : 1
                border.color: wallGrid.current === modelData.path ? Theme.primary
                                                                   : Theme.glass(Theme.outline_variant, 0.5)
                color: Theme.surface_container

                // `clip: true` only clips to the bounding box, not to `radius` —
                // the inset Image (a plain rectangle) would still paint its sharp
                // corners into the space the rounded border curves away from.
                // Same rounded-mask idiom as island/ScreenshotActivity.qml.
                Rectangle {
                    id: imageMask
                    anchors.fill: parent; anchors.margins: 2
                    radius: 8
                    color: "white"
                    opacity: 0
                    layer.enabled: true
                }
                Image {
                    anchors.fill: parent; anchors.margins: 2
                    source: "file://" + modelData.thumb
                    sourceSize { width: wallGrid.thumb * 2; height: wallGrid.thumbH * 2 }   // 2x display, never full-res
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: imageMask
                    }
                }
                TapHandler {
                    onTapped: {
                        wallGrid.previous = wallGrid.current;
                        wallGrid.current = modelData.path;   // optimistic
                        S.Backend.request("run_action",
                            { item: wallGrid.item.id, path: modelData.path }, null);
                    }
                }
            }
        }
    }
}
