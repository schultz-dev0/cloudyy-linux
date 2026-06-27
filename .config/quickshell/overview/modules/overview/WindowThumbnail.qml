pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import "../../../"
import "../../services"

Item {
    id: root

    required property var windowData
    required property var toplevel
    required property bool captureActive

    property bool interactive: false

    signal clicked(var windowData)

    readonly property bool hovered: interactive && clickArea.containsMouse
    // Show the fallback until we actually have a captured frame on screen.
    readonly property bool showFallback: !capture.hasContent
    readonly property string fallbackLabel: appLabel()

    clip: true

    function appLabel() {
        const raw = `${windowData?.class || windowData?.initialClass || windowData?.title || ""}`.trim();
        if (!raw.length)
            return "APP";
        const parts = raw.replace(/[-_.]+/g, " ").split(/\s+/).filter(part => part.length > 0);
        const label = parts.length > 1
            ? parts.slice(0, 2).map(part => part[0]).join("")
            : raw.slice(0, 3);
        return label.toUpperCase();
    }

    // Each thumbnail captures a single snapshot frame on overview open (cheap).
    // `captureSource` stays attached for the overview session — detaching it
    // drops the buffered frame, leaving the tile blank.
    ScreencopyView {
        id: capture

        anchors.fill: parent
        live: false
        paintCursor: false
        captureSource: root.captureActive && root.toplevel ? root.toplevel : null
        opacity: capture.hasContent ? 1 : 0
    }

    function grabFrame() {
        retryTimer.retryCount = 0;
        if (root.captureActive && root.toplevel)
            Qt.callLater(() => capture.captureFrame());
    }

    onCaptureActiveChanged: grabFrame()
    onToplevelChanged: grabFrame()
    Component.onCompleted: grabFrame()

    // Some windows report their toplevel a frame or two after the overlay opens.
    // Retry briefly until we get content, then stop. This never loops once a
    // frame lands or the source goes away.
    Timer {
        id: retryTimer

        property int retryCount: 0

        interval: 160
        repeat: true
        triggeredOnStart: false
        running: root.captureActive && root.toplevel && !capture.hasContent && retryCount < 6
        onTriggered: {
            retryCount += 1;
            capture.captureFrame();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 3
        visible: root.showFallback
        antialiasing: true
        color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
        border.width: 1

        Image {
            id: fallbackIcon

            property int sourceIndex: 0
            property var sources: HyprlandData.iconSourcesForWindow(root.windowData)

            anchors.centerIn: parent
            width: Math.min(parent.width - 4, root.interactive ? 36 : 24)
            height: Math.min(parent.height - 4, root.interactive ? 36 : 24)
            source: sources.length > sourceIndex ? sources[sourceIndex] : ""
            sourceSize: Qt.size(48, 48)
            fillMode: Image.PreserveAspectFit
            visible: source.length > 0 && status === Image.Ready

            onSourcesChanged: sourceIndex = 0
            onStatusChanged: {
                if (status === Image.Error && sourceIndex < sources.length - 1)
                    Qt.callLater(() => {
                        sourceIndex += 1;
                    });
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !fallbackIcon.visible
            text: root.fallbackLabel
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.max(8, Math.min(14, Math.round(Math.min(parent.width, parent.height) * 0.28)))
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 3
        visible: root.interactive && root.hovered
        color: "transparent"
        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.75)
        border.width: 2
        z: 2
    }

    MouseArea {
        id: clickArea

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        z: 3
        onClicked: root.clicked(root.windowData)
    }
}
