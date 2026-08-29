pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../.."
import "IslandPreviewDragPolicy.js" as DragPolicy

Rectangle {
    id: root

    required property var capture   // {id, kind, path, addedAt}
    signal dismissRequested(string id)

    width: 290
    height: 54
    radius: 0
    color: Theme.resin(Theme.resinFillAlpha)
    border.width: 1
    border.color: Theme.resinBorder
    antialiasing: true

    property bool _dragSession: false
    property bool _qtDragStarted: false

    Row {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Item {
            id: thumb
            width: 38; height: 38
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Theme.hairline
            }
            Image {
                visible: root.capture.kind === "screenshot"
                anchors.fill: parent
                source: "file://" + root.capture.path
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                // Without sourceSize, Qt decodes at the source's full
                // resolution and lets the GPU shrink it to this Item's
                // size — bilinear minification over a large ratio looks
                // soft rather than sharp. Decoding at exactly this Item's
                // physical pixel size (accounting for the screen's own
                // scale factor) is what actually looks crisp, and adapts
                // automatically to whatever screen this renders on.
                sourceSize.width: Math.round(thumb.width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(thumb.height * Screen.devicePixelRatio)
            }
            Text {
                visible: root.capture.kind === "recording"
                anchors.centerIn: parent
                text: "▶"
                color: Theme.accent
                font.pixelSize: 14
            }

            DragHandler {
                id: dragHandler
                target: null
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    const result = DragPolicy.onHandlerActiveChanged(
                        root._dragSession, root._qtDragStarted, active);
                    root._dragSession = result.dragSession;
                    root._qtDragStarted = result.qtDragStarted;
                    if (result.action === "start")
                        dragStartTimer.start();
                }
            }
            Timer {
                id: dragStartTimer
                interval: 0
                onTriggered: {
                    if (DragPolicy.shouldStartQtDrag(root._dragSession, root._qtDragStarted, dragHandler.active)) {
                        root._qtDragStarted = true;
                        thumb.grabToImage(result => {
                            dragSource.Drag.imageSource = result.url;
                            dragSource.Drag.hotSpot = Qt.point(thumb.width / 2, thumb.height / 2);
                            dragSource.Drag.active = true;
                        }, Qt.size(thumb.width, thumb.height));
                    }
                }
            }
            Item {
                id: dragSource
                anchors.fill: parent
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: {
                    "text/uri-list": "file://" + root.capture.path,
                    "text/plain": root.capture.path,
                    "x-special/gnome-copied-files": "copy\nfile://" + root.capture.path
                }
                Drag.onDragFinished: {
                    const result = DragPolicy.onDragFinished();
                    root._dragSession = result.dragSession;
                    root._qtDragStarted = result.qtDragStarted;
                    if (result.action === "dismiss")
                        root.dismissRequested(root.capture.id);
                }
            }
        }

        Column {
            width: parent.width - 38 - 8 - 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                width: parent.width
                text: root.capture.path.split("/").pop()
                color: Theme.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }
            Text {
                text: root.capture.kind
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }

    MouseArea {
        id: closeHover
        anchors { top: parent.top; right: parent.right }
        width: 20
        height: 20
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.dismissRequested(root.capture.id)

        Text {
            visible: closeHover.containsMouse
            anchors { top: parent.top; right: parent.right; margins: 6 }
            text: "×"
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }
}
