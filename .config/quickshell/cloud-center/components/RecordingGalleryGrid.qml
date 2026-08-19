import QtQuick
import QtQuick.Effects
import "RecordingState.js" as RecordingState
import ".."

// Newest-first thumbnail grid mixing screenshots + recordings. Missing
// thumbnails are requested lazily (only for delegates GridView actually
// instantiates, i.e. the visible ones) and deduped so a stalled/failed thumb
// isn't re-requested on every watch tick.
Item {
    id: grid
    required property var items
    signal actionRequested(string action, string path)
    signal ensureThumbNeeded(string path)

    property var requestedThumbs: ({})

    function fileUri(path) {
        if (!path)
            return "";
        return "file://" + path.split("/").map(seg => encodeURIComponent(seg)).join("/");
    }

    width: parent ? parent.width : 0
    height: view.height

    readonly property int columns: Math.max(2, Math.floor(width / 176))
    readonly property int cell: Math.floor(width / columns)

    component GalleryActionButton: Rectangle {
        id: actionButton
        required property string glyph
        required property string action
        property color glyphColor: "white"
        signal activated(string action)

        width: 24; height: 24; radius: 2
        color: buttonHover.hovered ? Theme.glass(Theme.primary, 0.55) : Theme.glass(Theme.scrim, 0.55)
        Text {
            anchors.centerIn: parent
            text: actionButton.glyph
            color: actionButton.glyphColor
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        }
        HoverHandler { id: buttonHover }
        TapHandler { onTapped: actionButton.activated(actionButton.action) }
    }

    GridView {
        id: view
        width: grid.columns * grid.cell
        anchors.horizontalCenter: parent.horizontalCenter
        height: Math.ceil(model.length / grid.columns) * cellHeight
        cellWidth: grid.cell
        cellHeight: grid.cell - 12
        interactive: false
        model: grid.items

        delegate: Item {
            id: tile
            required property var modelData
            width: view.cellWidth
            height: view.cellHeight

            readonly property bool isVideo: tile.modelData.kind === "recording"
            readonly property string thumbPath: tile.modelData.thumb_path || ""

            Component.onCompleted: {
                if (tile.thumbPath !== "")
                    return;
                const path = tile.modelData.path;
                if (grid.requestedThumbs[path])
                    return;
                grid.requestedThumbs[path] = true;
                grid.ensureThumbNeeded(path);
            }

            Rectangle {
                id: card
                anchors.fill: parent
                anchors.margins: 6
                radius: 2
                clip: true
                color: Theme.surface_container
                border { width: 1; color: Theme.hairline }

                Rectangle {
                    id: imageMask
                    anchors.fill: parent
                    radius: card.radius
                    color: "white"
                    opacity: 0
                    layer.enabled: true
                }

                Image {
                    id: thumbImage
                    anchors.fill: parent
                    visible: tile.thumbPath !== ""
                    source: tile.thumbPath !== "" ? "file://" + tile.thumbPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: imageMask }

                    readonly property string dragFileUri: grid.fileUri(tile.modelData.path)
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: {
                        "text/uri-list": dragFileUri ? (dragFileUri + "\r\n") : "",
                        "text/plain": dragFileUri,
                    }

                    DragHandler {
                        id: dragHandler
                        target: null
                        onActiveChanged: if (active) thumbImage.Drag.active = true
                    }
                }

                Text {
                    visible: !thumbImage.visible
                    anchors.centerIn: parent
                    text: tile.isVideo ? "\u{f0381}" : "\u{f02e9}"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 26
                           hintingPreference: Font.PreferVerticalHinting }
                }

                Rectangle {
                    anchors { left: parent.left; top: parent.top; margins: 6 }
                    width: 18; height: 18; radius: 2
                    color: Theme.glass(Theme.scrim, 0.55)
                    visible: tile.isVideo
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0381}"
                        color: "white"
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 24
                    color: Theme.glass(Theme.scrim, cardHover.hovered ? 0.62 : 0)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        visible: !cardHover.hovered
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        text: RecordingState.formatTimestamp(tile.modelData.mtime_ms)
                            + " · " + RecordingState.formatBytes(tile.modelData.size_bytes)
                        elide: Text.ElideRight
                        width: parent.width - 12
                        color: "white"
                        opacity: 0.85
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                }

                Row {
                    visible: cardHover.hovered
                    anchors.centerIn: parent
                    spacing: 4

                    GalleryActionButton {
                        glyph: "\u{f03cc}"; action: "open"
                        onActivated: action => grid.actionRequested(action, tile.modelData.path)
                    }
                    GalleryActionButton {
                        glyph: "\u{f018f}"; action: "copy"
                        onActivated: action => grid.actionRequested(action, tile.modelData.path)
                    }
                    GalleryActionButton {
                        glyph: "\u{f03eb}"; action: "edit"
                        onActivated: action => grid.actionRequested(action, tile.modelData.path)
                    }
                    GalleryActionButton {
                        glyph: "\u{f0770}"; action: "reveal"
                        onActivated: action => grid.actionRequested(action, tile.modelData.path)
                    }
                    GalleryActionButton {
                        glyph: "\u{f0a79}"; action: "delete"; glyphColor: Theme.error
                        onActivated: action => grid.actionRequested(action, tile.modelData.path)
                    }
                }

                HoverHandler { id: cardHover }
            }
        }
    }

    Text {
        visible: (grid.items || []).length === 0
        anchors.centerIn: parent
        text: "No screenshots or recordings yet"
        color: Theme.textMuted
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
               hintingPreference: Font.PreferVerticalHinting }
    }
}
