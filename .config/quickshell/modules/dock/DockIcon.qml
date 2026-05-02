import QtQuick
import Quickshell
import "../.."

Item {
    id: root

    required property var appData        // { class, exec, icon, isRunning, isPinned }
    required property int iconSize
    required property real maxScale
    required property real spread
    required property int frameMs
    required property real dockMouseX     // mouse X in iconsRow coordinates, -9999 = outside
    required property real iconCenterX    // center X of this icon in iconsRow coordinates

    signal clicked

    property bool hovered: false
    property bool pressed: false

    // ── Gaussian magnification ─────────────────────────────────────────────
    readonly property real targetScale: {
        if (dockMouseX < -1000)
            return 1.0;
        const d = Math.abs(dockMouseX - iconCenterX);
        const sigma = iconSize * spread;
        return 1.0 + (maxScale - 1.0) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
    }
    property real currentScale: 1.0

    Timer {
        interval: root.frameMs
        running: true
        repeat: true
        onTriggered: {
            const lerp = 1.0 - Math.exp(-12.0 * root.frameMs / 1000.0);
            root.currentScale += (root.targetScale - root.currentScale) * lerp;
        }
    }

    width: root.iconSize
    height: root.iconSize * root.maxScale + 6  // +6 for running dot below

    // ── Icon image ─────────────────────────────────────────────────────────
    Image {
        id: iconImg
        width: root.iconSize
        height: root.iconSize
        anchors {
            bottom: parent.bottom
            bottomMargin: 6  // space for running dot
            horizontalCenter: parent.horizontalCenter
        }
        
        property int fallbackStage: 0
        property string baseIcon: root.appData.icon ?? "application-x-executable"
        onBaseIconChanged: fallbackStage = 0

                source: {
            if (baseIcon.startsWith("/")) return "file://" + baseIcon
            const theme = parent.themeName || "Papirus-Dark"
            if (fallbackStage === 0) return `file:///usr/share/icons/${theme}/48x48/apps/${baseIcon}.svg`
            if (fallbackStage === 1) return `file:///usr/share/icons/${theme}/scalable/apps/${baseIcon}.svg`
            if (fallbackStage === 2) return `file:///usr/share/icons/${theme}/48x48/devices/${baseIcon}.svg`
            if (fallbackStage === 3) return `file:///usr/share/icons/${theme}/scalable/devices/${baseIcon}.svg`
            if (fallbackStage === 4) return `file:///usr/share/icons/${theme}/48x48/places/${baseIcon}.svg`
            if (fallbackStage === 5) return `file:///usr/share/icons/${theme}/scalable/places/${baseIcon}.svg`
            if (fallbackStage === 6) return `file:///usr/share/icons/${theme}/48x48/categories/${baseIcon}.svg`
            if (fallbackStage === 7) return `file:///usr/share/icons/${theme}/scalable/categories/${baseIcon}.svg`
            if (fallbackStage === 8) return `file:///usr/share/icons/Papirus-Dark/48x48/apps/${baseIcon}.svg`
            if (fallbackStage === 9) return `file:///usr/share/icons/Papirus-Dark/48x48/devices/${baseIcon}.svg`
            return `file:///usr/share/icons/${theme}/48x48/apps/application-x-executable.svg`
        }

        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
        smooth: true
        scale: root.currentScale
        transformOrigin: Item.Bottom

        onStatusChanged: {
            if (status === Image.Error && fallbackStage < 10) {
                fallbackStage++
            }
        }
    }

    // ── Running indicator dot ──────────────────────────────────────────────
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

    // ── Mouse interaction ──────────────────────────────────────────────────
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
