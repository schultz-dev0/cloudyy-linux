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

    property string systemIconTheme: "Papirus-Dark"
    Process {
        command: ["bash", "-c", "grep '^gtk-icon-theme-name=' ~/.config/gtk-3.0/settings.ini | cut -d= -f2"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t.length > 0) dock.systemIconTheme = t;
            }
        }
    }

    // ── Tunables ───────────────────────────────────────────────────────────
    readonly property int iconSize: 48
    readonly property real maxScale: 1.8
    readonly property real spread: 1
    readonly property int frameMs: 16
    readonly property int triggerHeight: 0
    readonly property int pillHeight: iconSize + paddingV * 2
    readonly property int dockBodyHeight: 110
    readonly property int iconSpacing: 25
    readonly property int paddingH: 14
    readonly property int paddingV: 12
    readonly property int bottomGap: 0
    readonly property int activationHeight: 16

    // ── Pinned apps — EDIT THIS ────────────────────────────────────────────
    readonly property var pinnedApps: [
        {
            class: "firefox",
            exec: "firefox",
            icon: "firefox"
        },
        {
            class: "dev.zed.Zed",
            exec: "zeditor",
            icon: "zed"
        },
        {
            class: "kitty",
            exec: "kitty",
            icon: "kitty"
        },
        {
            class: "thunar",
            exec: "thunar",
            icon: "xfce-filemanager"
        },
        {
            class: "spotify",
            exec: "spotify",
            icon: "spotify"
        }
        //{
        //class: "apps",
        //exec: ["/usr/bin/bash", "-c", "$HOME/cloudyy_scripts/rofi/applications.sh"],
        //icon: "kitty"
        //},
        ,
    ]

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: false
    property real dockMouseX: -9999
    readonly property bool anyFullscreen: {
        return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0);
    }
    onAnyFullscreenChanged: if (anyFullscreen)
        dockVisible = false

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var mergedApps: {
        const pinnedClasses = new Set(pinnedApps.map(a => a.class.toLowerCase()));
        const runningMap = {};
        HyprlandData.windowList.forEach(w => {
            const cls = (w.class || "").toLowerCase();
            if (cls && !runningMap[cls])
                runningMap[cls] = w;
        });

        const result = pinnedApps.map(app => ({
                    class: app.class,
                    exec: app.exec,
                    icon: app.icon,
                    isRunning: !!runningMap[app.class.toLowerCase()],
                    isPinned: true
                }));

        Object.keys(runningMap).forEach(cls => {
            if (!pinnedClasses.has(cls)) {
                const w = runningMap[cls];
                const rawIcon = (w.class || "").toLowerCase().replace(/\./g, "-");
                result.push({
                    class: w.class,
                    exec: w.class.toLowerCase(),
                    icon: rawIcon,
                    isRunning: true,
                    isPinned: false
                });
            }
        });

        return result;
    }

    // ── Dimensions ────────────────────────────────────────────────────────
    readonly property int dockFullHeight: dockBodyHeight + bottomGap + triggerHeight
    readonly property int dockWidth: mergedApps.length * (iconSize + iconSpacing)
                                     + iconSize + paddingH * 2

    // ── Window ────────────────────────────────────────────────────────────
    anchors {
        bottom: true
    }
    implicitWidth: dockWidth
    implicitHeight: dockVisible ? dockFullHeight : activationHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

    // ── Launch helper ──────────────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        console.log("Dock Launching:", JSON.stringify(cmd));
        const p = procProto.createObject(dock, {
            command: cmd
        });
        p.running = true;
    }

    // ── Dock body ──────────────────────────────────────────────────────────
    Item {
        id: dockBody
        width: dock.dockWidth
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
            width: parent.width
            height: dock.pillHeight
            anchors.bottom: parent.bottom
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.72)
        }

        // Icon row (search button pinned left + app icons)
        Row {
            anchors {
                bottom: parent.bottom
                bottomMargin: dock.paddingV
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            // Search button — always leftmost, never displaced by app list
            Item {
                width:  dock.iconSize
                height: dock.iconSize * dock.maxScale + 6

                Text {
                    width:  dock.iconSize
                    height: dock.iconSize
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 6
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                    text: "󰍉"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.round(dock.iconSize * 0.72)
                    color: Theme.on_surface
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch("exec quickshell ipc call spotlight toggle")
                }
            }

            Row {
                id: iconsRow
                spacing: dock.iconSpacing

                Repeater {
                    model: dock.mergedApps
                    DockIcon {
                        required property var modelData
                        required property int index
                        appData: modelData
                        iconSize: dock.iconSize
                        maxScale: dock.maxScale
                        spread: dock.spread
                        frameMs: dock.frameMs
                        dockMouseX: dock.dockMouseX
                        iconCenterX: x + dock.iconSize / 2
                        onClicked: {
                            if (modelData.isRunning)
                                Hyprland.dispatch("focuswindow class:" + modelData.class);
                            else {
                                const e = modelData.exec;
                                if (Array.isArray(e)) {
                                    dock.launch(e);
                                } else if (e) {
                                    dock.launch(["uwsm-app", "--", e]);
                                }
                            }
                        }
                    }
                }
            }
        }

        // HoverHandler tracks pointer inside dockBody without competing with
        // child MouseAreas for hover events — fixes hide timer firing on icon hover.
        HoverHandler {
            onHoveredChanged: {
                if (hovered) {
                    hideTimer.stop();
                } else {
                    dock.dockMouseX = -9999;
                    if (dock.dockVisible)
                        hideTimer.restart();
                }
            }
            onPointChanged: {
                if (hovered)
                    dock.dockMouseX = dockBody.mapToItem(iconsRow, point.position.x, point.position.y).x;
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
        width: dock.dockWidth
        height: dock.activationHeight
        hoverEnabled: true
        onEntered: {
            hideTimer.stop();
            dock.dockVisible = true;
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
        function toggle() {
            dock.dockVisible = !dock.dockVisible;
        }
        function show() {
            dock.dockVisible = true;
        }
        function hide() {
            dock.dockVisible = false;
        }
    }
}
