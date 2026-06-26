pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import "../../../"
import "../../services"

Item {
    id: root

    required property var windows
    required property var monitorData
    required property var toplevelByAddress
    required property bool overviewActive
    required property bool tileCaptureActive
    property int cornerRadius: 10
    property bool interactive: false

    signal requestFocusWindow(var windowData)

    clip: true

    function normalizeAddress(addr) {
        const s = `${addr ?? ""}`.trim().toLowerCase();
        if (!s.length)
            return "";
        return s.startsWith("0x") ? s : "0x" + s;
    }

    function toplevelForWindow(window) {
        const target = normalizeAddress(window?.address);
        if (!target.length)
            return null;
        if (toplevelByAddress[target])
            return toplevelByAddress[target];
        for (const t of ToplevelManager.toplevels?.values ?? []) {
            if (!t?.HyprlandToplevel?.address)
                continue;
            if (normalizeAddress(t.HyprlandToplevel.address) === target)
                return t;
        }
        return null;
    }

    readonly property var shownWindows: root.windowsToShow()

    function monitorUsableWidth() {
        const m = monitorData;
        if (!m)
            return 1920;
        const t = Number(m.transform ?? 0);
        const w = (t % 2 === 1) ? m.height : m.width;
        return Math.max(1, w - (m.reserved?.[0] ?? 0) - (m.reserved?.[2] ?? 0));
    }

    function monitorUsableHeight() {
        const m = monitorData;
        if (!m)
            return 1080;
        const t = Number(m.transform ?? 0);
        const h = (t % 2 === 1) ? m.width : m.height;
        return Math.max(1, h - (m.reserved?.[1] ?? 0) - (m.reserved?.[3] ?? 0));
    }

    readonly property real fitScale: Math.min(
        width / monitorUsableWidth(),
        height / monitorUsableHeight()
    )

    readonly property real canvasWidth: monitorUsableWidth() * fitScale
    readonly property real canvasHeight: monitorUsableHeight() * fitScale
    readonly property real canvasOffsetX: (width - canvasWidth) / 2
    readonly property real canvasOffsetY: (height - canvasHeight) / 2
    readonly property real originX: (monitorData?.x ?? 0) + (monitorData?.reserved?.[0] ?? 0)
    readonly property real originY: (monitorData?.y ?? 0) + (monitorData?.reserved?.[1] ?? 0)

    function windowsToShow() {
        const list = (windows ?? []).filter(w => Number(w.monitor) === Number(monitorData?.id ?? -1));
        const fs = list.find(w => (w.fullscreen ?? 0) > 0);
        if (fs)
            return [fs];
        return list
            .sort((a, b) => (b.size?.[0] * b.size?.[1]) - (a.size?.[0] * a.size?.[1]))
            .slice(0, 8);
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Theme.glassSection
        antialiasing: true
    }

    Item {
        id: monitorCanvas

        x: root.canvasOffsetX
        y: root.canvasOffsetY
        width: root.canvasWidth
        height: root.canvasHeight
        clip: true

        Repeater {
            model: root.shownWindows

            delegate: WindowThumbnail {
                required property var modelData

                x: ((modelData.at?.[0] ?? 0) - root.originX) * root.fitScale
                y: ((modelData.at?.[1] ?? 0) - root.originY) * root.fitScale
                width: Math.max(4, (modelData.size?.[0] ?? 100) * root.fitScale)
                height: Math.max(4, (modelData.size?.[1] ?? 100) * root.fitScale)
                windowData: modelData
                toplevel: root.toplevelForWindow(modelData)
                captureActive: root.overviewActive && root.tileCaptureActive
                interactive: root.interactive
                onClicked: windowData => root.requestFocusWindow(windowData)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.shownWindows.length === 0
        text: "empty"
        color: Theme.on_surface_variant
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
    }
}
