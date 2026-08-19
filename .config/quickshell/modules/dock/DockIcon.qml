import "../.."
import "../../overview/services"
// modules/dock/DockIcon.qml
import QtQuick
import Quickshell

Item {
    id: root

    required property var appData // { class, exec, icon, isRunning, isPinned, groupKey, windowCount, window? }
    required property real iconSize
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

    property bool pressed: false
    property bool leftDragging: false
    property real pressStartX: 0
    property int instanceIndex: 0

    signal clicked()
    signal contextMenuRequested(int instanceIndex)
    signal dragReorderStarted(int visualIndex, real centerBodyX, real centerBodyY)
    signal dragReorderMoved(real centerBodyX, real centerBodyY)
    signal dragReorderEnded()
    signal dragReorderCanceled()

    readonly property int windowCount: root.appData?.windowCount ?? 0
    readonly property bool multiWindow: root.windowCount > 1
    readonly property var groupWindows: {
        const _deps = HyprlandData.windowList;
        const gk = `${root.appData?.groupKey ?? ""}`.trim();
        return gk.length ? HyprlandData.windowsForGroupKey(gk) : [];
    }

    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1;
        const d = Math.abs(dockMouseX - iconCenterX);
        const sigma = iconSize * spread;
        return 1 + (maxScale - 1) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
    }
    property real currentScale: 1
    property real currentDragShiftX: 0

    readonly property real labelLiftPx: root.iconSize * Math.max(0, root.currentScale - 1)
    readonly property real pointerDeltaX: dockMouseX < -1000 ? 99999 : Math.abs(dockMouseX - iconCenterX)
    readonly property bool pointerOverIcon: root.pointerDeltaX <= root.iconSize * 0.72
    readonly property bool showInstanceControls: root.multiWindow && root.pointerOverIcon
    readonly property bool showHoverLabel: root.pointerOverIcon

    readonly property string hoverLabelText: {
        const app = root.appData;
        if (!app)
            return "";

        if (root.multiWindow) {
            const wins = root.groupWindows;
            if (wins.length > 1) {
                const idx = Math.max(0, Math.min(root.instanceIndex, wins.length - 1));
                return `${idx + 1}/${wins.length} — ${HyprlandData.windowLabel(wins[idx])}`;
            }
        }

        const groupLabel = `${app.groupLabel ?? ""}`.trim();
        if (groupLabel.length)
            return groupLabel;

        const identityLabel = `${app.label ?? app.identity?.label ?? ""}`.trim();
        if (identityLabel.length)
            return identityLabel;

        const entry = HyprlandData.desktopEntryForClass(app.class);
        const desktopName = `${entry?.name ?? entry?.Name ?? ""}`.trim();
        if (desktopName.length)
            return desktopName;

        if (app.window)
            return HyprlandData.windowLabel(app.window);

        return `${app.class ?? ""}`.trim();
    }

    property bool magnifyLatch: false

    z: isDragSource ? 80 : (showHoverLabel ? 40 : 0)

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6

    function syncInstanceToFocused() {
        const wins = root.groupWindows;
        if (wins.length === 0) {
            root.instanceIndex = 0;
            return;
        }

        let focused = null;
        let bestHistory = 999999;
        const list = HyprlandData.windowList ?? [];
        for (let i = 0; i < list.length; i++) {
            const w = list[i];
            const history = w?.focusHistoryID ?? 999999;
            if (history < bestHistory) {
                bestHistory = history;
                focused = w;
            }
        }

        const addr = HyprDispatch.normalizeAddress(focused?.address);
        let idx = 0;
        for (let j = 0; j < wins.length; j++) {
            if (HyprDispatch.normalizeAddress(wins[j].address) === addr) {
                idx = j;
                break;
            }
        }
        root.instanceIndex = idx;
    }

    function cycleInstance(delta) {
        const wins = root.groupWindows;
        if (wins.length <= 1)
            return;
        const n = wins.length;
        root.instanceIndex = (root.instanceIndex + delta + n) % n;
    }

    onDockDragActiveChanged: {
        if (!dockDragActive)
            currentDragShiftX = 0;
    }

    onDockIdleChanged: {
        if (dockIdle) {
            currentScale = 1;
            currentDragShiftX = 0;
            magnifyLatch = false;
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

            if (root.showInstanceControls && !root.magnifyLatch) {
                root.syncInstanceToFocused();
                root.magnifyLatch = true;
            } else if (!root.showInstanceControls) {
                root.magnifyLatch = false;
            }

            if (!root.dockDragActive)
                return;

            const shiftDelta = root.dragShiftTargetX - root.currentDragShiftX;
            if (Math.abs(shiftDelta) < 0.25)
                root.currentDragShiftX = root.dragShiftTargetX;
            else
                root.currentDragShiftX += shiftDelta * lerp;
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
                visible: root.multiWindow && !root.isDragSource
                width: countLabel.implicitWidth + 8
                height: 16
                radius: 2
                clip: true
                color: Theme.primary
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: -4
                    rightMargin: -4
                }

                DotTexture {
                    anchors.fill: parent
                    tint: Theme.on_primary
                    dotAlpha: 0.18
                    cell: 4
                    dotRadius: 0.6
                }

                Text {
                    id: countLabel
                    anchors.centerIn: parent
                    text: root.showInstanceControls
                        ? `${root.instanceIndex + 1}/${root.windowCount}`
                        : `${root.windowCount}`
                    color: Theme.on_primary
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
        }

        DockHoverLabel {
            anchorItem: iconContainer
            active: root.showHoverLabel
            label: root.hoverLabelText
            labelLiftPx: root.labelLiftPx
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

    WheelHandler {
        enabled: root.showInstanceControls && !root.dockDragActive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y === 0)
                return;
            root.cycleInstance(event.angleDelta.y < 0 ? 1 : -1);
            event.accepted = true;
        }
    }

    MouseArea {
        id: leftDragArea
        anchors.fill: parent
        enabled: !root.dockDragActive || root.isDragSource
        preventStealing: root.isDragSource
        acceptedButtons: Qt.LeftButton
        hoverEnabled: false
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
                return;
            }
            const p = root.mapToItem(dockBodyRef, mouse.x, mouse.y);
            root.dragReorderMoved(p.x, p.y);
        }
        onReleased: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.leftDragging)
                    root.dragReorderEnded();
                else
                    root.clicked();
            }
            root.pressed = false;
            root.leftDragging = false;
        }
        onCanceled: {
            if (root.leftDragging)
                root.dragReorderCanceled();
            root.pressed = false;
            root.leftDragging = false;
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: !root.dockDragActive
        onTapped: root.contextMenuRequested(root.instanceIndex)
    }

}
