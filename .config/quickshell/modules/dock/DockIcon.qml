import "../.."
import "../../overview/services"
// modules/dock/DockIcon.qml
import QtQuick
import Quickshell

Item {
    id: root

    required property var appData // { class, exec, icon, isRunning, isPinned }
    required property int iconSize
    required property real maxScale
    required property real spread
    required property int frameMs
    required property real dockMouseX // mouse X in iconsRow coordinates, -9999 = outside
    required property real iconCenterX // center X of this icon in iconsRow coordinates
    property bool hovered: false
    property bool pressed: false
    // ── Gaussian magnification ───────────────────────────────────────────────
    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1;

        const d = Math.abs(dockMouseX - iconCenterX);
        const sigma = iconSize * spread;
        return 1 + (maxScale - 1) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
    }
    property real currentScale: 1

    signal clicked()

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6 // +6 for running dot below

    Timer {
        interval: root.frameMs
        running: true
        repeat: true
        onTriggered: {
            const lerp = 1 - Math.exp(-12 * root.frameMs / 1000);
            root.currentScale += (root.targetScale - root.currentScale) * lerp;
        }
    }

    // ── Icon image ───────────────────────────────────────────────────────────
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
        onStatusChanged: {
            if (status === Image.Error && sourceIndex < sources.length - 1)
                Qt.callLater(() => {
                return sourceIndex++;
            });

        }

        anchors {
            bottom: parent.bottom
            bottomMargin: 6 // space for running dot
            horizontalCenter: parent.horizontalCenter
        }

    }

    // ── Running indicator dot ────────────────────────────────────────────────
    Rectangle {
        visible: root.appData.isRunning ?? false
        width: 4
        height: 4
        radius: 2
        color: Theme.primary

        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }

    }

    // ── Mouse interaction ────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: {
            root.hovered = false;
            root.pressed = false;
        }
        onPressed: root.pressed = true
        onReleased: root.pressed = false
        onClicked: root.clicked()
    }

}
