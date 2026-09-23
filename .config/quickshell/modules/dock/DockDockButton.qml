pragma ComponentBehavior: Bound

import QtQuick
import "../.."

// Shared magnify dock button (search, folders, apps, …)
Item {
    id: root

    required property real iconSize
    required property real maxScale
    required property real spread
    required property int frameMs
    required property real dockMouseX
    required property real btnCenterX
    required property bool animationActive

    property string glyph: ""
    property string imageSource: ""
    property string hoverLabel: ""
    property bool cropImage: false
    property bool draggable: false
    property bool dropHighlight: false

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal dragStarted(real globalX, real globalY)
    signal dragMoved(real globalX, real globalY)
    signal dragEnded(real globalX, real globalY)
    signal dragCanceled()

    property bool pressed: false
    property bool leftDragging: false
    property real pressStartX: 0
    property real pressStartY: 0

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6

    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1.0;
        const d = Math.abs(dockMouseX - btnCenterX);
        const sigma = iconSize * spread;
        let scale = 1.0 + (maxScale - 1.0) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
        if (root.dropHighlight)
            scale = Math.max(scale, maxScale * 0.95);
        return scale;
    }

    property real currentScale: 1.0

    readonly property real labelLiftPx: root.iconSize * Math.max(0, root.currentScale - 1)
    readonly property real pointerDeltaX: dockMouseX < -1000 ? 99999 : Math.abs(dockMouseX - btnCenterX)
    property point dockPointer: Qt.point(-99999, -99999)
    // Pointer's y must be inside the drawn, scaled icon — not the tray
    // padding. Factored out so right/middle-click TapHandlers can gate on
    // this alone: the x half below uses the smoothed dockMouseX, which lags
    // ~100ms and can drop a fast click past the cell.
    readonly property bool pointerInIconHeight: {
        iconContainer.scale; // re-evaluate while magnifying
        const p = iconContainer.mapFromGlobal(root.dockPointer.x, root.dockPointer.y);
        return p.y >= 0 && p.y <= iconContainer.height;
    }
    // x-band as before (gaps between icons are intentionally fine).
    readonly property bool pointerOverIcon: root.pointerDeltaX <= root.iconSize * 0.72 && root.pointerInIconHeight

    z: pointerOverIcon && hoverLabel.length > 0 ? 40 : 0

    Timer {
        interval: root.frameMs
        running: root.animationActive
        repeat: true
        onTriggered: {
            const delta = root.targetScale - root.currentScale;
            if (Math.abs(delta) < 0.005) {
                root.currentScale = root.targetScale;
                return;
            }
            const lerp = 1.0 - Math.exp(-12.0 * root.frameMs / 1000.0);
            root.currentScale += delta * lerp;
        }
    }

    Item {
        id: iconContainer
        anchors {
            bottom: parent.bottom
            bottomMargin: 6
            horizontalCenter: parent.horizontalCenter
        }
        width: root.iconSize
        height: root.iconSize
        scale: root.currentScale
        transformOrigin: Item.Bottom
        opacity: root.leftDragging ? 0.35 : 1.0

        // Inside iconContainer, not on it: the pointerOverIcon /
        // containmentMask y test must keep measuring along the dock's own axis.
        DockUpright {
            Image {
                visible: root.imageSource.length > 0
                anchors.fill: parent
                source: root.imageSource
                fillMode: root.cropImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            Text {
                visible: root.imageSource.length === 0
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.glyph
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.round(root.iconSize * 0.72)
                color: root.dropHighlight ? Theme.accent : Theme.text
            }

            Rectangle {
                anchors.fill: parent
                radius: 2
                color: "transparent"
                border.color: Theme.accent
                border.width: root.dropHighlight ? 2 : 0
                visible: root.dropHighlight
            }
        }
    }

    DockHoverLabel {
        anchorItem: iconContainer
        active: root.pointerOverIcon
        label: root.hoverLabel
        labelLiftPx: root.labelLiftPx
    }

    MouseArea {
        id: buttonArea
        anchors.fill: parent
        // Full cell width, but only the drawn icon's height is clickable.
        containmentMask: QtObject {
            // Typed signature required: an untyped contains() is not
            // invokable as a mask — Qt silently ignores it (only a log
            // warning) and the tall hit area comes back.
            function contains(point: point): bool {
                const p = buttonArea.mapToItem(iconContainer, point.x, point.y);
                return p.y >= 0 && p.y <= iconContainer.height;
            }
        }
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: root.leftDragging
        onClicked: {
            if (!root.leftDragging)
                root.clicked();
        }
        onPressed: mouse => {
            root.pressed = true;
            root.pressStartX = mouse.x;
            root.pressStartY = mouse.y;
            root.leftDragging = false;
        }
        onPositionChanged: mouse => {
            if (!root.pressed || !root.draggable)
                return;
            if (!root.leftDragging) {
                const dx = mouse.x - root.pressStartX;
                const dy = mouse.y - root.pressStartY;
                if (Math.hypot(dx, dy) <= 10)
                    return;
                root.leftDragging = true;
                const g = root.mapToGlobal(mouse.x, mouse.y);
                root.dragStarted(g.x, g.y);
                return;
            }
            const g = root.mapToGlobal(mouse.x, mouse.y);
            root.dragMoved(g.x, g.y);
        }
        onReleased: mouse => {
            if (root.leftDragging) {
                const g = root.mapToGlobal(mouse.x, mouse.y);
                root.dragEnded(g.x, g.y);
            }
            root.pressed = false;
            root.leftDragging = false;
        }
        onCanceled: {
            if (root.leftDragging)
                root.dragCanceled();
            root.pressed = false;
            root.leftDragging = false;
        }
    }

    // Both gate on the vertical test only — a TapHandler already only fires
    // inside its own cell, so the laggy x half of pointerOverIcon would just
    // drop taps after a fast move.
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: !root.leftDragging && root.pointerInIconHeight
        onTapped: root.rightClicked()
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: !root.leftDragging && root.pointerInIconHeight
        onTapped: root.middleClicked()
    }
}
