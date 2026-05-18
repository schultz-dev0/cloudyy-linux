import "../.."
import "../../overview/services"
// modules/dock/DockIcon.qml
import QtQuick
import Quickshell

Item {
    id: root

    required property var appData // { class, exec, icon, isRunning, isPinned, window? }
    required property int iconSize
    required property real maxScale
    required property real spread
    required property int frameMs
    required property real dockMouseX
    required property real iconCenterX
    required property var dockBodyRef
    required property var iconsRowRef
    required property int visualIndex
    property bool isDragSource: false

    property bool hovered: false
    property bool pressed: false
    property bool leftDragging: false
    property real pressStartX: 0

    signal clicked()
    signal requestTogglePin()
    signal dragReorderStarted(int visualIndex, real centerBodyX, real centerBodyY)
    signal dragReorderMoved(real centerBodyX, real centerBodyY)
    signal dragReorderEnded()

    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1;
        const d = Math.abs(dockMouseX - iconCenterX);
        const sigma = iconSize * spread;
        return 1 + (maxScale - 1) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
    }
    property real currentScale: 1

    z: isDragSource ? 80 : 0

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6

    Timer {
        interval: root.frameMs
        running: true
        repeat: true
        onTriggered: {
            const lerp = 1 - Math.exp(-12 * root.frameMs / 1000);
            root.currentScale += (root.targetScale - root.currentScale) * lerp;
        }
    }

    Image {
        id: iconImg

        property int sourceIndex: 0
        property var sources: HyprlandData.iconSourcesForName(root.appData.icon ?? "application-x-executable")

        width: root.iconSize
        height: root.iconSize
        onSourcesChanged: sourceIndex = 0
        source: sources[sourceIndex] ?? "image://icon/application-x-executable"
        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        smooth: true
        scale: root.currentScale
        transformOrigin: Item.Bottom
        opacity: root.isDragSource ? 0.2 : 1
        onStatusChanged: {
            if (status === Image.Error && sourceIndex < sources.length - 1)
                Qt.callLater(() => {
                    sourceIndex++;
                });
        }

        anchors {
            bottom: parent.bottom
            bottomMargin: 6
            horizontalCenter: parent.horizontalCenter
        }

    }

    Rectangle {
        visible: (root.appData.isRunning ?? false) && !root.isDragSource
        width: 4
        height: 4
        radius: 2
        color: Theme.primary

        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }

    }

    MouseArea {
        id: leftDragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false;
            if (!pressed) {
                root.pressed = false;
                root.leftDragging = false;
            }
        }
        onPressed: mouse => {
            root.pressed = true;
            root.pressStartX = mouse.x;
            root.leftDragging = false;
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (!root.leftDragging) {
                if (Math.abs(mouse.x - root.pressStartX) > 10) {
                    root.leftDragging = true;
                    const p = root.mapToItem(dockBodyRef, mouse.x, mouse.y);
                    root.dragReorderStarted(root.visualIndex, p.x, p.y);
                }
            }
            if (root.leftDragging) {
                const p = root.mapToItem(dockBodyRef, mouse.x, mouse.y);
                root.dragReorderMoved(p.x, p.y);
            }
        }
        onReleased: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.leftDragging) {
                    root.dragReorderEnded();
                    root.leftDragging = false;
                } else {
                    root.clicked();
                }
            }
            root.pressed = false;
        }
        onCanceled: {
            if (root.leftDragging) {
                root.dragReorderEnded();
                root.leftDragging = false;
            }
            root.pressed = false;
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.WithinBounds | TapHandler.ReleaseWithinBounds
        onTapped: root.requestTogglePin()
    }

}
