import "../.."
import "../../overview/services"
// modules/dock/DockIcon.qml
import QtQuick
import Quickshell

Item {
    id: root

    required property var appData // { class, exec, icon, isRunning, isPinned, groupKey, windowCount, window? }
    required property int iconSize
    required property real maxScale
    required property real spread
    required property int frameMs
    required property real dockMouseX
    required property real iconCenterX
    required property var dockBodyRef
    required property var iconsRowRef
    required property int visualIndex
    required property bool animationActive
    required property bool dockIdle
    property bool dockDragActive: false
    property bool isDragSource: false
    property real dragShiftTargetX: 0

    property bool hovered: false
    property bool pressed: false
    property bool leftDragging: false
    property real pressStartX: 0

    signal clicked()
    signal contextMenuRequested()
    signal exposeRequested()
    signal dragReorderStarted(int visualIndex, real centerBodyX, real centerBodyY)
    signal dragReorderMoved(real centerBodyX, real centerBodyY)
    signal dragReorderEnded()
    signal dragReorderCanceled()

    readonly property bool canExpose: (root.appData?.isRunning ?? false)
        && (root.appData.windowCount ?? 0) > 1
        && `${root.appData.groupKey ?? ""}`.length > 0

    readonly property int exposeHoldMs: 400

    property bool exposeTriggered: false

    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1;
        const d = Math.abs(dockMouseX - iconCenterX);
        const sigma = iconSize * spread;
        return 1 + (maxScale - 1) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
    }
    property real currentScale: 1
    property real currentDragShiftX: 0

    z: isDragSource ? 80 : 0

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6

    onDockDragActiveChanged: {
        if (!dockDragActive)
            currentDragShiftX = 0;
    }

    onDockIdleChanged: {
        if (dockIdle) {
            currentScale = 1;
            currentDragShiftX = 0;
        }
    }

    Timer {
        interval: root.frameMs
        running: root.animationActive
        repeat: true
        onTriggered: {
            const lerp = 1 - Math.exp(-12 * root.frameMs / 1000);

            const scaleDelta = root.targetScale - root.currentScale;
            if (Math.abs(scaleDelta) < 0.005)
                root.currentScale = root.targetScale;
            else
                root.currentScale += scaleDelta * lerp;

            if (!root.dockDragActive)
                return;

            const shiftDelta = root.dragShiftTargetX - root.currentDragShiftX;
            if (Math.abs(shiftDelta) < 0.25)
                root.currentDragShiftX = root.dragShiftTargetX;
            else
                root.currentDragShiftX += shiftDelta * lerp;
        }
    }

    Timer {
        id: exposeHoldTimer
        interval: root.exposeHoldMs
        repeat: false
        onTriggered: {
            if (!root.pressed || !root.canExpose)
                return;
            root.exposeTriggered = true;
            root.exposeRequested();
        }
    }

    Item {
        id: visualLayer
        width: parent.width
        height: parent.height
        x: root.currentDragShiftX

        Item {
            id: iconContainer

            width: root.iconSize
            height: root.iconSize
            scale: root.currentScale
            transformOrigin: Item.Bottom
            opacity: root.isDragSource ? 0.2 : 1

            anchors {
                bottom: parent.bottom
                bottomMargin: 6
                horizontalCenter: parent.horizontalCenter
            }

            AppIcon {
                anchors.fill: parent
                iconSize: root.iconSize
                appData: root.appData
            }

            Rectangle {
                visible: (root.appData.windowCount ?? 0) > 1 && !root.isDragSource
                width: countLabel.implicitWidth + 8
                height: 16
                radius: 8
                color: Theme.primary
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: -4
                    rightMargin: -4
                }

                Text {
                    id: countLabel
                    anchors.centerIn: parent
                    text: `${root.appData.windowCount ?? 0}`
                    color: Theme.on_primary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
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
    }

    MouseArea {
        id: leftDragArea
        anchors.fill: parent
        enabled: !root.dockDragActive || root.isDragSource
        preventStealing: root.isDragSource
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
            root.exposeTriggered = false;
            if (root.canExpose)
                exposeHoldTimer.restart();
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            if (!root.leftDragging) {
                if (Math.abs(mouse.x - root.pressStartX) > 10) {
                    exposeHoldTimer.stop();
                    root.leftDragging = true;
                    const p = root.mapToItem(dockBodyRef, mouse.x, mouse.y);
                    root.dragReorderStarted(root.visualIndex, p.x, p.y);
                }
                return;
            }
            const p = root.mapToItem(dockBodyRef, mouse.x, mouse.y);
            root.dragReorderMoved(p.x, p.y);
        }
        onReleased: mouse => {
            exposeHoldTimer.stop();
            if (mouse.button === Qt.LeftButton) {
                if (root.leftDragging)
                    root.dragReorderEnded();
                else if (!root.exposeTriggered)
                    root.clicked();
            }
            root.exposeTriggered = false;
            root.pressed = false;
            root.leftDragging = false;
        }
        onCanceled: {
            exposeHoldTimer.stop();
            if (root.leftDragging)
                root.dragReorderCanceled();
            root.pressed = false;
            root.leftDragging = false;
            root.exposeTriggered = false;
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: !root.dockDragActive
        onTapped: root.contextMenuRequested()
    }

}
