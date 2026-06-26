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
    property bool snapshotOnly: false

    signal clicked(var windowData)

    readonly property bool hovered: interactive && clickArea.containsMouse

    clip: true

    ScreencopyView {
        id: capture

        anchors.fill: parent
        live: false
        paintCursor: false
        captureSource: root.captureActive && root.toplevel ? root.toplevel : null
        opacity: hasContent ? 1 : 0
    }

    Timer {
        id: frameTimer

        interval: 400
        running: root.captureActive && root.toplevel && !root.snapshotOnly
        repeat: true
        onTriggered: capture.captureFrame()
    }

    function captureOnce() {
        if (captureActive && toplevel)
            Qt.callLater(() => capture.captureFrame());
    }

    onToplevelChanged: captureOnce()

    onCaptureActiveChanged: {
        if (captureActive && snapshotOnly)
            captureOnce();
        else if (captureActive && toplevel)
            captureOnce();
    }

    Rectangle {
        anchors.fill: parent
        radius: 3
        visible: !capture.hasContent
        antialiasing: true
        color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
        border.width: 1

        Image {
            id: fallbackIcon

            property int sourceIndex: 0
            property var sources: HyprlandData.iconSourcesForWindow(root.windowData)

            anchors.centerIn: parent
            width: Math.min(parent.width - 4, 20)
            height: Math.min(parent.height - 4, 20)
            source: sources.length > sourceIndex ? sources[sourceIndex] : ""
            sourceSize: Qt.size(40, 40)
            fillMode: Image.PreserveAspectFit
            visible: source.length > 0

            onSourcesChanged: sourceIndex = 0
            onStatusChanged: {
                if (status === Image.Error && sourceIndex < sources.length - 1)
                    Qt.callLater(() => {
                        sourceIndex += 1;
                    });
            }
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
