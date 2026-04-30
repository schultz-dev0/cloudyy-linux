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
    readonly property int   triggerHeight: 0
    readonly property int   interact:      dockBodyHeight  // clickable zone height = bar height
    readonly property int   iconSpacing:   25
    readonly property int   paddingH:      14
    readonly property int   paddingV:      12
    readonly property int   bottomGap:     0

    // ── Pinned apps — EDIT THIS ────────────────────────────────────────────
    readonly property var pinnedApps: [
        { class: "firefox",        exec: "firefox",     icon: "firefox"   },
        { class: "dev.zed.Zed",    exec: "zeditor",     icon: "zed"       },
        { class: "kitty",          exec: "kitty",        icon: "kitty"     },
        { class: "thunar",         exec: "thunar",       icon: "thunar"    },
        { class: "spotify",        exec: "spotify",      icon: "spotify"   },
    ]

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: false
    property real dockMouseX:  -9999
    readonly property bool anyFullscreen: {
        return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0)
    }
    onAnyFullscreenChanged: if (anyFullscreen) dockVisible = false

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var mergedApps: {
        const pinnedClasses = new Set(pinnedApps.map(a => a.class.toLowerCase()))
        const runningMap = {}
        HyprlandData.windowList.forEach(w => {
            const cls = (w.class || "").toLowerCase()
            if (cls && !runningMap[cls]) runningMap[cls] = w
        })

        const result = pinnedApps.map(app => ({
            class:     app.class,
            exec:      app.exec,
            icon:      app.icon,
            isRunning: !!runningMap[app.class.toLowerCase()],
            isPinned:  true
        }))

        Object.keys(runningMap).forEach(cls => {
            if (!pinnedClasses.has(cls)) {
                const w = runningMap[cls]
                const rawIcon = (w.class || "").toLowerCase().replace(/\./g, "-")
                result.push({
                    class:     w.class,
                    exec:      w.class.toLowerCase(),
                    icon:      rawIcon,
                    isRunning: true,
                    isPinned:  false
                })
            }
        })

        return result
    }

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
        p.runningChanged.connect(() => { if (!p.running) p.destroy() })
        p.running = true
    }

    // ── Interact zone — sized to the bar, registers icon hover/position for magnification ──
    MouseArea {
        id: dockHoverArea
        width:  dock.implicitWidth
        height: dock.interact
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        enabled: dock.dockVisible
        onPositionChanged: mouse => {
            dock.dockMouseX = mapToItem(iconsRow, mouse.x, mouse.y).x
        }
        onEntered: hideTimer.stop()
        onExited: {
            dock.dockMouseX = -9999
            hideTimer.restart()
        }
    }

    // ── Dock body ──────────────────────────────────────────────────────────
    Item {
        id: dockBody
        width:  dock.dockWidth
        height: dock.dockBodyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: dock.dockVisible ? 0 : dock.dockFullHeight
        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

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
    }

    // ── Autohide trigger strip ─────────────────────────────────────────────
    MouseArea {
        id: triggerZone
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        width:  dock.triggerWidth
        height: dock.triggerHeight + 2
        hoverEnabled: true
        enabled: !dock.dockVisible
        onEntered: {
            hideTimer.stop()
            dock.dockVisible = true
        }
    }

    // ── Hide delay timer ───────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 500
        repeat: false
        onTriggered: dock.dockVisible = false
    }

    // ── IPC ────────────────────────────────────────────────────────────────
    IpcHandler {
        target: "dock"
        function toggle() { dock.dockVisible = !dock.dockVisible }
        function show()   { dock.dockVisible = true }
        function hide()   { dock.dockVisible = false }
    }
}
