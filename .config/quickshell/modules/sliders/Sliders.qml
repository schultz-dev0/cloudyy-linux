pragma ComponentBehavior: Bound

// modules/sliders/Sliders.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."

Scope {
    id: sliders

    property string osdKind: ""

    property real volumeValue: 50
    property bool volumeMuted: false
    property real brightnessValue: 50
    property bool nightLightAvailable: false
    property bool nightLightActive: false
    property int nightLightTemp: 3500
    property int pendingNightLightTemp: 3500

    readonly property bool osdVisible: osdKind !== ""
    readonly property string volumeIcon: volumeMuted ? "󰖁" : (volumeValue < 33 ? "󰕿" : volumeValue < 66 ? "󰕾" : "󱄠")
    readonly property string osdIcon: osdKind === "brightness" ? "󰃠" : volumeIcon
    readonly property string osdValueLabel: osdKind === "brightness"
        ? Math.round(brightnessValue) + "%"
        : (volumeMuted ? "Muted" : Math.round(volumeValue) + "%")
    readonly property real osdProgress: osdKind === "brightness"
        ? Math.max(0, Math.min(1, brightnessValue / 100))
        : (volumeMuted ? 0 : Math.max(0, Math.min(1, volumeValue / 100)))

    Component {
        id: procProto
        Process {}
    }

    component IconButton: Rectangle {
        id: button
        required property string icon
        signal clicked()

        width: 30
        height: 30
        radius: 10
        color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.55)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: button.icon
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            anchors.fill: parent
            onClicked: button.clicked()
        }
    }

    component PillSlider: Slider {
        id: control

        implicitHeight: 26
        live: true

        background: Rectangle {
            x: control.leftPadding
            y: control.topPadding + control.availableHeight / 2 - height / 2
            width: control.availableWidth
            height: 10
            radius: 999
            color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.45)

            Rectangle {
                width: control.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: control.palette.highlight
                opacity: control.enabled ? 1 : 0.35
            }
        }

        handle: Rectangle {
            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
            y: control.topPadding + control.availableHeight / 2 - height / 2
            width: 16
            height: 16
            radius: 8
            color: control.pressed ? Theme.primary : Theme.on_surface
            border.color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
            border.width: 1
            opacity: control.enabled ? 1 : 0.4
        }
    }

    function launch(cmd) {
        const p = procProto.createObject(sliders, {
            command: cmd
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function refreshAll() {
        refreshVolume();
        refreshBrightness();
        refreshNightLight();
    }

    function refreshVolume() {
        volumeState.running = false;
        volumeState.command = ["bash", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"];
        volumeState.running = true;
    }

    function refreshBrightness() {
        brightnessState.running = false;
        brightnessState.command = ["bash", "-lc", "brightnessctl -m 2>/dev/null | awk -F, '{gsub(/%/, \"\", $4); print $4}'"];
        brightnessState.running = true;
    }

    function refreshNightLight() {
        nightLightState.running = false;
        nightLightState.command = ["bash", "-lc", "if ! command -v hyprsunset >/dev/null 2>&1; then echo 'available=0'; exit 0; fi; active=0; if pgrep -x hyprsunset >/dev/null 2>&1; then active=1; fi; temp=$(cat \"$HOME/.cache/wltemp\" 2>/dev/null || echo 3500); printf 'available=1 active=%s temp=%s\\n' \"$active\" \"$temp\""];
        nightLightState.running = true;
    }

    function scheduleRefresh() {
        stateRefreshTimer.restart();
    }

    function setVolume(value) {
        const target = Math.max(0, Math.min(100, Math.round(value)));
        volumeValue = target;
        if (target > 0)
            volumeMuted = false;
        launch(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", target + "%"]);
        if (target > 0)
            launch(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
        showVolume();
    }

    function toggleMute() {
        launch(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        showVolume();
    }

    function setBrightness(value) {
        const target = Math.max(1, Math.min(100, Math.round(value)));
        brightnessValue = target;
        launch(["brightnessctl", "set", target + "%", "-q"]);
        showBrightness();
    }

    function toggleNightLight() {
        if (!nightLightAvailable)
            return;

        if (nightLightActive) {
            launch(["bash", "-lc", "if ! systemctl --user stop hyprsunset.service >/dev/null 2>&1; then pid=$(pgrep -x hyprsunset | head -n1); [ -n \"$pid\" ] && kill \"$pid\"; fi"]);
            nightLightActive = false;
        } else {
            const temp = Math.round(nightLightTemp);
            launch(["bash", "-lc", "temp=" + temp + "; if ! systemctl --user start hyprsunset.service >/dev/null 2>&1 && ! pgrep -x hyprsunset >/dev/null 2>&1; then hyprsunset >/dev/null 2>&1 & fi; sleep 0.2; hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; mkdir -p \"$HOME/.cache\"; printf '%s' \"$temp\" > \"$HOME/.cache/wltemp\""]);
            nightLightActive = true;
        }

        scheduleRefresh();
    }

    function setNightLightTemp(value) {
        if (!nightLightAvailable)
            return;

        pendingNightLightTemp = Math.max(1000, Math.min(6500, Math.round(value)));
        nightLightTemp = pendingNightLightTemp;
        nightLightWriteTimer.restart();
    }

    function writeNightLightTemp() {
        const temp = Math.max(1000, Math.min(6500, Math.round(pendingNightLightTemp)));
        launch(["bash", "-lc", "temp=" + temp + "; mkdir -p \"$HOME/.cache\"; printf '%s' \"$temp\" > \"$HOME/.cache/wltemp\"; if pgrep -x hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; fi"]);
        scheduleRefresh();
    }

    function showVolume() {
        osdKind = "volume";
        refreshVolume();
        osdTimer.restart();
        scheduleRefresh();
    }

    function showBrightness() {
        osdKind = "brightness";
        refreshBrightness();
        osdTimer.restart();
        scheduleRefresh();
    }

    function hideOsd() {
        osdKind = "";
    }

    Process {
        id: volumeState

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const muted = line.includes("[MUTED]");
                const match = line.match(/([0-9]*\.?[0-9]+)/);
                if (match) {
                    sliders.volumeValue = Math.max(0, Math.min(100, Math.round(parseFloat(match[1]) * 100)));
                    sliders.volumeMuted = muted;
                }
            }
        }
    }

    Process {
        id: brightnessState

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parsed = parseFloat(line.trim());
                if (!Number.isNaN(parsed))
                    sliders.brightnessValue = Math.max(1, Math.min(100, parsed));
            }
        }
    }

    Process {
        id: nightLightState

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const availableMatch = line.match(/available=(\d)/);
                const activeMatch = line.match(/active=(\d)/);
                const tempMatch = line.match(/temp=(\d+)/);
                sliders.nightLightAvailable = availableMatch ? availableMatch[1] === "1" : false;
                sliders.nightLightActive = activeMatch ? activeMatch[1] === "1" : false;
                if (tempMatch)
                    sliders.nightLightTemp = parseInt(tempMatch[1], 10);
            }
        }
    }

    Timer {
        id: osdTimer
        interval: 1200
        repeat: false
        onTriggered: sliders.hideOsd()
    }

    Timer {
        id: stateRefreshTimer
        interval: 150
        repeat: false
        onTriggered: sliders.refreshAll()
    }

    Timer {
        id: nightLightWriteTimer
        interval: 200
        repeat: false
        onTriggered: sliders.writeNightLightTemp()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property var modelData

            screen: modelData
            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: sliders.osdVisible ? 86 : 0
            exclusiveZone: 0
            visible: sliders.osdVisible
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay

            Rectangle {
                width: 280
                height: 64
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 16
                radius: 20
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.92)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.28)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    Text {
                        text: sliders.osdIcon
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 10
                        Layout.alignment: Qt.AlignVCenter
                        radius: 999
                        color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.45)

                        Rectangle {
                            width: parent.width * sliders.osdProgress
                            height: parent.height
                            radius: parent.radius
                            color: Theme.primary
                        }
                    }

                    Text {
                        text: sliders.osdValueLabel
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sliders"

        function showVolume() {
            sliders.showVolume();
        }

        function showBrightness() {
            sliders.showBrightness();
        }

        function hide() {
            sliders.hideOsd();
        }
    }

    Component.onCompleted: refreshAll()
}
