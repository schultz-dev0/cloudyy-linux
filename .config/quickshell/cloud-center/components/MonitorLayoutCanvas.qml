pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: canvas

    property var monitors: []
    property string selectedName: ""
    property color backgroundColor: "#e7eeeb"
    property color monitorColor: "#d4dfdb"
    property color selectedColor: "#c2ddd5"
    property color borderColor: "#94aaa3"
    property color accentColor: "#087b68"
    property color textColor: "#22332e"
    property color mutedColor: "#6e817b"

    signal selected(string name)
    signal moved(string name, int x, int y)

    implicitHeight: 200

    function logicalSize(monitor) {
        let width = Number(monitor.width ?? 0);
        let height = Number(monitor.height ?? 0);
        const match = String(monitor.mode ?? "").match(/(?:^|\s)(\d+)x(\d+)@/);
        if (match) {
            width = Number(match[1]);
            height = Number(match[2]);
        }
        if ((Number(monitor.transform ?? 0) % 2) === 1)
            [width, height] = [height, width];
        const scale = Number(monitor.scale ?? 1) || 1;
        return {
            width: Math.max(1, Math.round(width / scale)),
            height: Math.max(1, Math.round(height / scale)),
        };
    }

    function calculateBounds() {
        if (canvas.monitors.length === 0)
            return { minX: 0, minY: 0, maxX: 1, maxY: 1 };
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const monitor of canvas.monitors) {
            const size = canvas.logicalSize(monitor);
            const x = Number(monitor.x ?? 0), y = Number(monitor.y ?? 0);
            minX = Math.min(minX, x); minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + size.width); maxY = Math.max(maxY, y + size.height);
        }
        return { minX, minY, maxX, maxY };
    }

    readonly property var layoutBounds: calculateBounds()
    readonly property real spanX: Math.max(1, layoutBounds.maxX - layoutBounds.minX)
    readonly property real spanY: Math.max(1, layoutBounds.maxY - layoutBounds.minY)
    readonly property real previewScale: Math.max(0.001,
        Math.min((width - 48) / spanX, (height - 48) / spanY))

    function snapPosition(movingName, rawX, rawY) {
        const moving = canvas.monitors.find(monitor => monitor.name === movingName);
        if (!moving) return { x: Math.round(rawX), y: Math.round(rawY) };
        const movingSize = canvas.logicalSize(moving);
        const threshold = Math.max(1, 30 / canvas.previewScale);
        let bestX = rawX, bestY = rawY;
        let distanceX = threshold + 1, distanceY = threshold + 1;
        const xCandidates = [0], yCandidates = [0];
        for (const other of canvas.monitors) {
            if (other.name === movingName) continue;
            const size = canvas.logicalSize(other);
            const x = Number(other.x ?? 0), y = Number(other.y ?? 0);
            xCandidates.push(x, x + size.width, x - movingSize.width, x + size.width - movingSize.width);
            yCandidates.push(y, y + size.height, y - movingSize.height, y + size.height - movingSize.height);
        }
        for (const candidate of xCandidates) {
            const distance = Math.abs(rawX - candidate);
            if (distance < distanceX) { bestX = candidate; distanceX = distance; }
        }
        for (const candidate of yCandidates) {
            const distance = Math.abs(rawY - candidate);
            if (distance < distanceY) { bestY = candidate; distanceY = distance; }
        }
        return {
            x: Math.round(distanceX <= threshold ? bestX : rawX),
            y: Math.round(distanceY <= threshold ? bestY : rawY),
        };
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: canvas.backgroundColor
        border { width: 1; color: canvas.borderColor }
    }

    Repeater {
        model: canvas.monitors
        delegate: Rectangle {
            id: monitorRect
            required property var modelData
            readonly property var layoutSize: canvas.logicalSize(monitorRect.modelData)
            readonly property bool isSelected: monitorRect.modelData.name === canvas.selectedName

            x: 24 + (Number(monitorRect.modelData.x ?? 0) - canvas.layoutBounds.minX) * canvas.previewScale
            y: 24 + (Number(monitorRect.modelData.y ?? 0) - canvas.layoutBounds.minY) * canvas.previewScale
            width: Math.max(30, layoutSize.width * canvas.previewScale)
            height: Math.max(30, layoutSize.height * canvas.previewScale)
            radius: 7
            color: isSelected ? canvas.selectedColor : canvas.monitorColor
            opacity: monitorRect.modelData.enabled === false ? 0.55 : 1
            border { width: isSelected ? 2 : 1; color: isSelected ? canvas.accentColor : canvas.borderColor }

            Column {
                anchors.centerIn: parent
                spacing: 3
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: monitorRect.modelData.name
                    color: canvas.textColor
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; bold: true }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: monitorRect.width > 100 && monitorRect.height > 55
                    text: {
                        const size = monitorRect.layoutSize;
                        return size.width + "×" + size.height + " logical";
                    }
                    color: canvas.mutedColor
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 8 }
                }
            }

            DragHandler {
                id: drag
                target: null
                property real startX: 0
                property real startY: 0
                onActiveChanged: {
                    if (!active) return;
                    canvas.selectedName = monitorRect.modelData.name;
                    canvas.selected(monitorRect.modelData.name);
                    startX = Number(monitorRect.modelData.x ?? 0);
                    startY = Number(monitorRect.modelData.y ?? 0);
                }
                onTranslationChanged: {
                    if (!active) return;
                    const snapped = canvas.snapPosition(
                        monitorRect.modelData.name,
                        startX + translation.x / canvas.previewScale,
                        startY + translation.y / canvas.previewScale);
                    canvas.moved(monitorRect.modelData.name, snapped.x, snapped.y);
                }
            }
            TapHandler {
                onTapped: {
                    canvas.selectedName = monitorRect.modelData.name;
                    canvas.selected(monitorRect.modelData.name);
                }
            }
        }
    }
}
