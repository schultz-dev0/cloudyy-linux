import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../.."
import "../../overview/services"

PanelWindow {
    id: dock

    // ── Tunables ───────────────────────────────────────────────────────────
    readonly property int   iconSize:      48
    readonly property real  maxScale:      1.8
    readonly property real  spread:        2.2
    readonly property int   frameMs:       16
    readonly property int   triggerWidth:  320
    readonly property int   triggerHeight: 4
    readonly property int   iconSpacing:   10
    readonly property int   paddingH:      14
    readonly property int   paddingV:      12
    readonly property int   bottomGap:     10

    // ── Pinned apps — EDIT THIS ────────────────────────────────────────────
    readonly property var pinnedApps: [
        { class: "firefox",        exec: "firefox",     icon: "firefox"   },
        { class: "dev.zed.Zed",    exec: "zeditor",     icon: "zed"       },
        { class: "kitty",          exec: "kitty",        icon: "kitty"     },
        { class: "thunar",         exec: "thunar",       icon: "thunar"    },
        { class: "spotify",        exec: "spotify",      icon: "spotify"   },
    ]

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: true  // always visible for now, autohide added in Task 5
    property real dockMouseX:  -9999

    // ── App list (pinned only for now, running merge in Task 6) ───────────
    readonly property var mergedApps: pinnedApps.map(a => ({
        class:    a.class,
        exec:     a.exec,
        icon:     a.icon,
        isRunning: false,
        isPinned: true
    }))

    // ── Dimensions ────────────────────────────────────────────────────────
    readonly property int dockBodyHeight: Math.ceil(iconSize * maxScale) + paddingV * 2 + 6
    readonly property int dockFullHeight: dockBodyHeight + bottomGap + triggerHeight
    readonly property int dockWidth: mergedApps.length * (iconSize + iconSpacing)
                                     - iconSpacing + paddingH * 2

    // ── Window ────────────────────────────────────────────────────────────
    anchors { bottom: true }
    implicitWidth:  Math.max(dockWidth, triggerWidth + paddingH * 2)
    implicitHeight: dockFullHeight
    exclusiveZone:  0
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

    // ── Launch helper ──────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        const p = procProto.createObject(dock, { command: cmd })
        p.running = true
    }

    // ── Dock body ──────────────────────────────────────────────────────────
    Item {
        id: dockBody
        width:  dock.dockWidth
        height: dock.dockBodyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0  // autohide animation added in Task 5

        // Glass pill background
        Rectangle {
            anchors.fill: parent
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Qt.rgba(Theme.surface_container.r,
                           Theme.surface_container.g,
                           Theme.surface_container.b, 0.72)
            border.color: Qt.rgba(Theme.outline_variant.r,
                                  Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.18)
            border.width: 1

            // Top-edge glass shine
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
                radius: parent.radius
            }
        }

        // Icon row
        Row {
            id: iconsRow
            anchors {
                verticalCenter: parent.verticalCenter
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            Repeater {
                model: dock.mergedApps
                DockIcon {
                    required property var  modelData
                    required property int  index
                    appData:      modelData
                    iconSize:     dock.iconSize
                    maxScale:     dock.maxScale
                    spread:       dock.spread
                    frameMs:      dock.frameMs
                    dockMouseX:   dock.dockMouseX
                    iconCenterX:  x + dock.iconSize / 2
                    onClicked: {
                        if (modelData.isRunning)
                            Hyprland.dispatch("focuswindow class:" + modelData.class)
                        else
                            dock.launch(["uwsm-app", "--", modelData.exec])
                    }
                }
            }
        }

        // Mouse tracking for Gaussian magnification
        MouseArea {
            id: dockHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true
            onPositionChanged: mouse => {
                dock.dockMouseX = mapToItem(iconsRow, mouse.x, mouse.y).x
            }
            onExited: dock.dockMouseX = -9999
        }
    }
}
