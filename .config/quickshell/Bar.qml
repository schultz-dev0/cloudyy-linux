import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import Quickshell.Io
import "overview/services"

PanelWindow {
    id: bar

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int barHeight: 40
    readonly property int topGap: 6
    readonly property int sideGap: 10
    readonly property int radius: 14
    readonly property int pillRadius: 10
    readonly property int pillPadH: 8
    readonly property int pillPadV: 5
    readonly property int pillGap: 4
    readonly property real bgOpacity: 0.88

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool notifOpen: false
    property bool dnd: false
    signal notifToggle

    // ── Window ────────────────────────────────────────────────────────────────
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: topGap
        left: sideGap
        right: sideGap
    }
    implicitHeight: barHeight + topGap
    exclusiveZone: barHeight + topGap
    color: "transparent"

    // ── One-shot command launcher ─────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        const p = procProto.createObject(bar, {
            command: cmd
        });
        p.running = true;
    }

    // ── Module component ──────────────────────────────────────────────────────
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property int iconSize: 12
        property color fg: Theme.on_surface
        property color bg: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.6)
        property bool hoverable: true
        signal clicked
        signal scrollUp
        signal scrollDown

        height: bar.barHeight - bar.pillPadV * 2
        implicitWidth: pillText.implicitWidth
        radius: bar.pillRadius
        color: bg

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: pill.iconSize
            font.weight: Font.DemiBold
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: pill.hoverable
            onClicked: pill.clicked()
            onWheel: e => {
                e.angleDelta.y > 0 ? pill.scrollUp() : pill.scrollDown();
            }
            onEntered: if (pill.hoverable)
                pill.color = Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.9)
            onExited: pill.color = pill.bg
        }
    }

    // ── Bar background ────────────────────────────────────────────────────────
    Rectangle {
        id: barBg
        anchors {
            top: parent.top
            topMargin: bar.topGap
            left: parent.left
            right: parent.right
        }
        height: bar.barHeight
        radius: bar.radius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, bar.bgOpacity)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)
        border.width: 1

        // ── LEFT ─────────────────────────────────────────────────────────────
        Row {
            anchors {
                left: parent.left
                leftMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: bar.pillGap

            Pill {
                label: "󰅟"
                iconSize: 18
                width: implicitWidth + bar.pillPadH * 2
                fg: Theme.on_primary_container
                bg: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.85)
                onClicked: bar.launch(["bash", "-c", "~/cloudyy_scripts/rofi/main.sh"])
            }

            Pill {
                id: clockPill
                property string t: Qt.formatDateTime(new Date(), "hh:mm")
                label: t
                width: implicitWidth + bar.pillPadH * 2
                fg: Theme.on_secondary_container
                bg: Qt.rgba(Theme.secondary_container.r, Theme.secondary_container.g, Theme.secondary_container.b, 0.45)
                Timer {
                    interval: 10000
                    running: true
                    repeat: true
                    onTriggered: clockPill.t = Qt.formatDateTime(new Date(), "hh:mm")
                }
                onClicked: bar.launch(["uwsm-app", "--", "gnome-clocks"])
            }

            Pill {
                id: updatesPill
                property string n: "0"
                label: "󰏔 " + n
                width: implicitWidth + bar.pillPadH * 2
                onClicked: bar.launch(["bash", "-c", "kitty --title cloudyy-updater ~/cloudyy_scripts/cloudyy-updater.sh & sleep 0.5; hyprctl dispatch focuswindow title:cloudyy-updater"])
                Timer {
                    interval: 3600000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: updatesProc.running = true
                }
                Process {
                    id: updatesProc
                    command: ["bash", "-c", "checkupdates 2>/dev/null | wc -l || echo 0"]
                    stdout: SplitParser {
                        onRead: d => updatesPill.n = d.trim()
                    }
                }
            }

            Pill {
                id: notifBell
                label: bar.dnd ? "󰂛" : "󰂚"
                width: implicitWidth + bar.pillPadH * 2
                iconSize: 14
                onClicked: bar.notifToggle()
            }
        }

        // ── CENTER ────────────────────────────────────────────────────────────
        Row {
            anchors.centerIn: parent
            spacing: bar.pillGap

            Pill {
                label: "󰕣"
                iconSize: 14
                width: implicitWidth + bar.pillPadH * 2
                fg: GlobalStates.overviewOpen ? Theme.on_primary_container : Theme.on_surface_variant
                bg: GlobalStates.overviewOpen ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.85) : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.5)
                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
            }

            Rectangle {
                height: bar.barHeight - bar.pillPadV * 2
                radius: bar.pillRadius + 2
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.5)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.1)
                border.width: 1
                width: wsRow.implicitWidth + 8

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 6

                    Repeater {
                        model: Array.from({
                            length: 6
                        }, (_, i) => i + 1)

                        delegate: Rectangle {
                            required property int modelData
                            readonly property var ws: Array.from(Hyprland.workspaces.values).find(w => w.id === modelData) ?? null
                            readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                            readonly property bool empty: ws === null

                            height: bar.barHeight - bar.pillPadV * 2 - 6
                            width: focused ? 26 : (empty ? 20 : 22)
                            radius: 8
                            anchors.verticalCenter: parent.verticalCenter
                            color: focused ? Theme.primary_container : (empty ? Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.18) : Qt.rgba(Theme.surface_container_highest.r, Theme.surface_container_highest.g, Theme.surface_container_highest.b, 0.6))

                            Behavior on width {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutQuad
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: String(modelData)
                                color: focused ? Theme.on_primary_container : (empty ? Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g, Theme.on_surface_variant.b, 0.35) : Theme.on_surface)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Hyprland.dispatch("workspace " + modelData)
                                onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace e-1" : "workspace e+1")
                            }
                        }
                    }
                }
            }
        }

        // ── RIGHT ─────────────────────────────────────────────────────────────
        Row {
            anchors {
                right: parent.right
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            spacing: bar.pillGap

            // Mpris
            Pill {
                id: mprisPill
                readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
                visible: player !== null && (player.playbackState === MprisPlaybackState.Playing || player.playbackState === MprisPlaybackState.Paused)
                label: {
                    if (!player)
                        return "";
                    const icon = player.playbackState === MprisPlaybackState.Playing ? "▶ " : "⏸ ";
                    return icon + (player.trackTitle ?? "").substring(0, 18);
                }
                width: visible ? Math.max(implicitWidth + bar.pillPadH * 2, 60) : 0
                fg: Theme.on_secondary_container
                bg: Qt.rgba(Theme.secondary_container.r, Theme.secondary_container.g, Theme.secondary_container.b, 0.45)
                onClicked: if (player)
                    player.togglePlaying()
                onScrollUp: if (player)
                    player.next()
                onScrollDown: if (player)
                    player.previous()
            }

            // Network
            Pill {
                id: netPill
                property string lbl: "󰤨"
                label: lbl
                width: implicitWidth + bar.pillPadH * 2
                iconSize: 14
                Timer {
                    interval: 5000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: netProc.running = true
                }
                Process {
                    id: netProc
                    command: ["bash", "-c", "nmcli -t -f active,ssid,signal dev wifi 2>/dev/null | awk -F: '/^yes/{print $2\" \"$3\"%\"}' | head -1 || echo OFF"]
                    stdout: SplitParser {
                        onRead: d => {
                            const s = d.trim();
                            netPill.lbl = s === "OFF" ? "󰖪" : "󰤨 " + s;
                        }
                    }
                }
                onClicked: bar.launch(["bash", "-c", "uwsm-app -- ~/cloudyy_scripts/cloud-center --wifi"])
            }

            // Volume
            Pill {
                id: volPill
                property string lbl: "󰕾"
                label: lbl
                width: implicitWidth + bar.pillPadH * 2
                iconSize: 14
                Timer {
                    interval: 2000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: volProc.running = true
                }
                Process {
                    id: volProc
                    command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
                    stdout: SplitParser {
                        onRead: d => {
                            const muted = d.includes("[MUTED]");
                            const m = d.match(/[\d.]+/);
                            if (m) {
                                const v = Math.round(parseFloat(m[0]) * 100);
                                volPill.lbl = muted ? "󰖁" : (v < 33 ? "󰕿 " : v < 66 ? "󰕾 " : "󱄠 ") + v + "%";
                            }
                        }
                    }
                }
                onClicked: bar.launch(["bash", "-c", "uwsm-app -- ~/cloudyy_scripts/cloud-center --audio"])
                onScrollUp: bar.launch(["bash", "-c", "swayosd-client --output-volume raise"])
                onScrollDown: bar.launch(["bash", "-c", "swayosd-client --output-volume lower"])
            }

            // CPU
            Pill {
                id: cpuPill
                property string lbl: "󰍛 ?"
                label: lbl
                width: implicitWidth + bar.pillPadH * 2
                fg: Theme.on_surface_variant
                Timer {
                    interval: 2000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: cpuProc.running = true
                }
                Process {
                    id: cpuProc
                    command: ["bash", "-c", "python3 -c 'import psutil; print(int(psutil.cpu_percent(0.3)))' 2>/dev/null || cut -d' ' -f1 /proc/loadavg"]
                    stdout: SplitParser {
                        onRead: d => cpuPill.lbl = "󰍛 " + d.trim() + "%"
                    }
                }
                onClicked: bar.launch(["bash", "-c", "kitty --title btop btop & sleep 0.5; hyprctl dispatch focuswindow title:btop"])
            }

            // Memory
            Pill {
                id: memPill
                property string lbl: "󰘚"
                label: lbl
                width: implicitWidth + bar.pillPadH * 2
                fg: Theme.on_surface_variant
                Timer {
                    interval: 2000
                    running: true
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: memProc.running = true
                }
                Process {
                    id: memProc
                    command: ["bash", "-c", "free | awk '/Mem:/{printf \"%d\", $3/$2*100}'"]
                    stdout: SplitParser {
                        onRead: d => memPill.lbl = "󰘚 " + d.trim() + "%"
                    }
                }
                onClicked: bar.launch(["bash", "-a", "~/cloudyy_scripts/cloudyy-other/RAMtui"])
            }

            // Battery
            Pill {
                id: batPill
                visible: UPower.displayDevice.isPresent
                readonly property real pct: UPower.displayDevice.percentage
                readonly property int bstate: UPower.displayDevice.state
                readonly property bool charging: bstate === UPowerDeviceState.Charging || bstate === UPowerDeviceState.PendingCharge
                readonly property bool full: bstate === UPowerDeviceState.FullyCharged
                label: {
                    if (full)
                        return "󰁹 Full";
                    if (charging)
                        return "󰂄 " + Math.round(pct) + "%";
                    const icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂"];
                    return icons[Math.min(Math.floor(pct / 11), 9)] + " " + Math.round(pct) + "%";
                }
                width: visible ? implicitWidth + bar.pillPadH * 2 : 0
                fg: charging || full ? Theme.tertiary : (pct < 15 ? Theme.on_error_container : Theme.on_surface)
                bg: charging || full ? Qt.rgba(Theme.tertiary_container.r, Theme.tertiary_container.g, Theme.tertiary_container.b, 0.3) : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.6)
            }

            // Power
            Pill {
                label: "󰐥"
                iconSize: 14
                width: implicitWidth + bar.pillPadH * 2
                fg: Theme.on_primary_container
                bg: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.85)
                onClicked: bar.launch(["bash", "-c", "~/cloudyy_scripts/wlogout.sh"])
            }
        }
    }
}
