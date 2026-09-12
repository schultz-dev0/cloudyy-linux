pragma ComponentBehavior: Bound

// modules/sliders/Sliders.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../../overview/services"
import "../toast" as QuickToast
import "../../Readout.js" as Readout

Scope {
    id: sliders

    property string osdKind: ""

    property real volumeValue: 50
    property bool volumeMuted: false
    property real brightnessValue: 50
    property real kbdBrightnessValue: 0
    property real kbdBrightnessMax: 3
    property bool nightLightAvailable: false
    property bool nightLightActive: false
    property int nightLightTemp: 3500
    property int pendingNightLightTemp: 3500
    property bool _nightLightReapplyTempAfterToggle: false
    property bool _osdAwaitingRefresh: false

    readonly property bool osdVisible: osdKind !== ""
    readonly property string volumeIcon: volumeMuted ? "󰖁" : (volumeValue < 33 ? "󰕿" : volumeValue < 66 ? "󰕾" : "󱄠")
    readonly property string osdIcon: osdKind === "brightness" ? "󰃠" : (osdKind === "kbdbrightness" ? "󰌌" : (osdKind === "nightlight" ? "󰖙" : volumeIcon))
    readonly property string osdValueLabel: Readout.osdLabel(
        osdKind, volumeValue, volumeMuted, brightnessValue,
        kbdBrightnessValue, kbdBrightnessMax, nightLightTemp)
    readonly property real osdProgress: {
        if (osdKind === "brightness") return Math.max(0, Math.min(1, brightnessValue / 100));
        if (osdKind === "kbdbrightness") return kbdBrightnessMax > 0 ? Math.max(0, Math.min(1, kbdBrightnessValue / kbdBrightnessMax)) : 0;
        if (osdKind === "nightlight") return Math.max(0, Math.min(1, (nightLightTemp - 1000) / 5500));
        return volumeMuted ? 0 : Math.max(0, Math.min(1, volumeValue / 100));
    }

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
        color: Qt.rgba(Theme.surfaceOverlay.r, Theme.surfaceOverlay.g, Theme.surfaceOverlay.b, 0.55)
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.3)
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: button.icon
            color: Theme.text
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
            color: Qt.rgba(Theme.surfaceOverlay.r, Theme.surfaceOverlay.g, Theme.surfaceOverlay.b, 0.45)

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
            color: control.pressed ? Theme.accent : Theme.text
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

    function nightLightScriptPath() {
        const h = (HyprlandData.homeDir || "").trim();
        if (h.length > 0)
            return "cloudyy-slider-nightlight";
        return "";
    }

    function nightLightExecArgv(mode, arg2) {
        if (mode === "toggle")
            return ["bash", "-lc", "exec cloudyy-slider-nightlight toggle"];
        return ["bash", "-lc", "exec cloudyy-slider-nightlight set " + String(arg2)];
    }

    function refreshAll() {
        refreshVolume();
        refreshBrightness();
        refreshNightLight();
    }

    function refreshVolume() {
        volumeState.running = false;
        volumeState.command = ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"];
        volumeState.running = true;
    }

    function refreshBrightness() {
        brightnessState.running = false;
        brightnessState.command = ["bash", "-lc", "exec cloudyy-slider-brightness get"];
        brightnessState.running = true;
    }

    function refreshNightLight() {
        nightLightState.running = false;
        nightLightState.command = ["sh", "-c", "if ! command -v hyprsunset >/dev/null 2>&1; then echo 'available=0'; exit 0; fi; active=0; if [ -f \"$HOME/.cache/wlnight_active\" ] && [ \"$(tr '[:upper:]' '[:lower:]' < \"$HOME/.cache/wlnight_active\")\" = true ]; then active=1; fi; temp=$(cat \"$HOME/.cache/wltemp\" 2>/dev/null || echo 3500); printf 'available=1 active=%s temp=%s\\n' \"$active\" \"$temp\""];
        nightLightState.running = true;
    }

    function scheduleRefresh() {
        stateRefreshTimer.restart();
    }

    function setVolume(value, showOsd) {
        const target = Math.max(0, Math.min(100, Math.round(value)));
        volumeValue = target;
        if (target > 0)
            volumeMuted = false;
        volumeWriteTimer.restart();
        if (showOsd !== false) {
            osdKind = "volume";
            _osdAwaitingRefresh = false;
            _pushOsdBurst();
        }
    }

    function toggleMute() {
        launch(["wpctl", "-c", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        showVolume();
    }

    function setBrightness(value, showOsd) {
        const target = Math.max(1, Math.min(100, Math.round(value)));
        brightnessValue = target;
        brightnessWriteTimer.restart();
        if (showOsd !== false) {
            osdKind = "brightness";
            _osdAwaitingRefresh = false;
            _pushOsdBurst();
        }
    }

    function toggleNightLight() {
        if (!nightLightAvailable)
            return;

        const turningOn = !nightLightActive;
        _nightLightReapplyTempAfterToggle = turningOn;
        if (turningOn)
            pendingNightLightTemp = nightLightTemp;

        nightLightToggleProc.running = false;
        nightLightToggleProc.command = nightLightExecArgv("toggle", 0);
        nightLightToggleProc.running = true;

        nightLightActive = !nightLightActive;
    }

    function setNightLightTemp(value, showOsd) {
        if (!nightLightAvailable)
            return;

        pendingNightLightTemp = Math.max(1000, Math.min(6500, Math.round(value)));
        nightLightTemp = pendingNightLightTemp;
        if (showOsd !== false) {
            osdKind = "nightlight";
            _osdAwaitingRefresh = false;
            _pushOsdBurst();
        }
    }

    function scheduleNightLightCommit() {
        nightLightWriteTimer.restart();
    }

    function commitNightLightTemp() {
        nightLightWriteTimer.stop();
        writeNightLightTemp();
    }

    function scheduleBrightnessCommit() {
        brightnessDdcTimer.restart();
    }

    function commitBrightness() {
        brightnessDdcTimer.stop();
        const target = Math.round(brightnessValue);
        brightnessDdcProc.running = false;
        brightnessDdcProc.command = ["bash", "-lc", "exec cloudyy-slider-brightness set-ddc " + target];
        brightnessDdcProc.running = true;
    }

    function writeNightLightTemp() {
        const temp = Math.round(pendingNightLightTemp);
        // Direct hyprctl — the bin script retries with sleeps and lags a drag.
        nightLightWriteProc.running = false;
        nightLightWriteProc.command = ["hyprctl", "hyprsunset", "temperature", String(temp)];
        nightLightWriteProc.running = true;
        nightLightCacheProc.running = false;
        nightLightCacheProc.command = ["sh", "-c", "printf '%s' '" + temp + "' > \"${XDG_CACHE_HOME:-$HOME/.cache}/wltemp\""];
        nightLightCacheProc.running = true;
    }

    function _pushOsdBurst() {
        QuickToast.ToastQueueService.showOsdBurst(
            osdKind, osdIcon, osdValueLabel, osdProgress);
    }

    function showVolume() {
        osdKind = "volume";
        _osdAwaitingRefresh = true;
        refreshVolume();
    }

    function showBrightness() {
        osdKind = "brightness";
        _osdAwaitingRefresh = true;
        refreshBrightness();
    }

    function showKbdBrightness(level, max) {
        kbdBrightnessValue = level;
        if (max > 0)
            kbdBrightnessMax = max;
        osdKind = "kbdbrightness";
        _pushOsdBurst();
    }

    function showNightLight() {
        osdKind = "nightlight";
        _osdAwaitingRefresh = true;
        refreshNightLight();
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
                    if (sliders.osdKind === "volume" && sliders._osdAwaitingRefresh) {
                        sliders._osdAwaitingRefresh = false;
                        sliders._pushOsdBurst();
                    }
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
                if (!Number.isNaN(parsed)) {
                    sliders.brightnessValue = Math.max(1, Math.min(100, parsed));
                    if (sliders.osdKind === "brightness" && sliders._osdAwaitingRefresh) {
                        sliders._osdAwaitingRefresh = false;
                        sliders._pushOsdBurst();
                    }
                }
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
                if (tempMatch) {
                    const t = parseInt(tempMatch[1], 10);
                    sliders.nightLightTemp = t;
                    sliders.pendingNightLightTemp = t;
                }
                if (sliders.osdKind === "nightlight" && sliders._osdAwaitingRefresh) {
                    sliders._osdAwaitingRefresh = false;
                    sliders._pushOsdBurst();
                }
            }
        }
    }

    Process {
        id: nightLightToggleProc
        running: false
        command: ["bash", "-lc", "true"]

        stdout: StdioCollector {
            id: nightLightToggleCollector
            onStreamFinished: {
                sliders.refreshNightLight();
                if (sliders._nightLightReapplyTempAfterToggle && sliders.nightLightActive) {
                    sliders.pendingNightLightTemp = sliders.nightLightTemp;
                    sliders.writeNightLightTemp();
                }
                sliders._nightLightReapplyTempAfterToggle = false;
                Qt.callLater(() => sliders.refreshNightLight());
            }
        }
    }

    Timer {
        id: stateRefreshTimer
        interval: 150
        repeat: false
        onTriggered: sliders.refreshAll()
    }

    Timer {
        id: volumeWriteTimer
        interval: 150
        repeat: false
        onTriggered: {
            const target = Math.round(sliders.volumeValue);
            volumeWriteProc.running = false;
            volumeWriteProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", target + "%"];
            volumeWriteProc.running = true;
            if (target > 0) {
                volumeUnmuteProc.running = false;
                volumeUnmuteProc.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"];
                volumeUnmuteProc.running = true;
            }
        }
    }

    Process { id: volumeWriteProc }
    Process { id: volumeUnmuteProc }

    Timer {
        id: brightnessWriteTimer
        interval: 150
        repeat: false
        onTriggered: {
            const target = Math.round(sliders.brightnessValue);
            brightnessWriteProc.running = false;
            brightnessWriteProc.command = ["bash", "-lc", "exec cloudyy-slider-brightness set-fast " + target];
            brightnessWriteProc.running = true;
        }
    }

    Process { id: brightnessWriteProc }

    Timer {
        id: brightnessDdcTimer
        interval: 400
        repeat: false
        onTriggered: sliders.commitBrightness()
    }

    Timer {
        id: nightLightWriteTimer
        interval: 400
        repeat: false
        onTriggered: sliders.writeNightLightTemp()
    }

    Process { id: nightLightWriteProc }
    Process { id: nightLightCacheProc }
    Process { id: brightnessDdcProc }

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
