pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: timerWindow

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property int panelWidth:  340
    readonly property int panelRadius: 20
    readonly property int padding:     16

    // ── History state ─────────────────────────────────────────────────────
    property var historyEntries: []
    readonly property string _historyFile:
        TimerService.homeDir + "/Desktop/timer_record/" + Qt.formatDate(new Date(), "yyyy-MM") + ".md"

    Process {
        id: historyReader
        command: ["bash", "-c", "cat '" + timerWindow._historyFile + "' 2>/dev/null"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("| ") || line.startsWith("| Started") || line.startsWith("|---")) return
                const parts = line.split("|").map(s => s.trim()).filter(s => s.length > 0)
                if (parts.length < 3) return
                timerWindow.historyEntries = timerWindow.historyEntries.concat([{
                    started:  parts[0],
                    label:    parts[1],
                    duration: parts[2],
                    mode:     parts[3] || ""
                }])
            }
        }
        onRunningChanged: {
            if (!running)
                timerWindow.historyEntries = timerWindow.historyEntries.slice().reverse()
        }
    }

    Process {
        id: fileOpener
        command: ["xdg-open", timerWindow._historyFile]
        running: false
    }

    // ── Local form state ──────────────────────────────────────────────────
    property bool showingNewForm: false
    onShowingNewFormChanged: {
        if (showingNewForm)
            newTimerForm.activate();
    }

    readonly property int _keyboardFocusMode: {
        if (!TimerService.open)
            return WlrKeyboardFocus.None;
        if (timerWindow.showingNewForm)
            return WlrKeyboardFocus.Exclusive;
        return WlrKeyboardFocus.OnDemand;
    }

    // ── Window ────────────────────────────────────────────────────────────
    anchors { bottom: true; left: true }
    margins { bottom: 16; left: 16 }
    implicitWidth:  panelWidth
    implicitHeight: panelRect.implicitHeight
    color:          "transparent"
    visible:        TimerService.open

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:timer"
    WlrLayershell.keyboardFocus: timerWindow._keyboardFocusMode
    WlrLayershell.exclusiveZone: 0

    onVisibleChanged: {
        if (visible) {
            historyReader.running = false
            timerWindow.historyEntries = []
            historyReader.running = true
        }
    }

    // ── Panel shell ───────────────────────────────────────────────────────
    Rectangle {
        id: panelRect
        focus: timerWindow.showingNewForm
        Keys.onEscapePressed: {
            if (timerWindow.showingNewForm) {
                timerWindow.showingNewForm = false
            } else {
                TimerService.open = false
            }
        }
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        implicitHeight: contentCol.implicitHeight + timerWindow.padding * 2
        radius: timerWindow.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        opacity: TimerService.open ? 1 : 0
        Behavior on opacity {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(160); easing.type: Easing.OutCubic }
        }
        scale: TimerService.open ? 1.0 : 0.88
        transformOrigin: Item.BottomLeft
        Behavior on scale {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(180); easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: contentCol
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                margins: timerWindow.padding
            }
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "⏱  Timers"
                    color: Theme.on_surface
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    font.family: "JetBrainsMono Nerd Font"
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: !timerWindow.showingNewForm
                    implicitWidth: newBtnLabel.implicitWidth + 16
                    implicitHeight: 24
                    radius: 12
                    color: Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.8)

                    Text {
                        id: newBtnLabel
                        anchors.centerIn: parent
                        text: "+ New"
                        color: Theme.on_primary_container
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        font.family: "JetBrainsMono Nerd Font"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: timerWindow.showingNewForm = true
                    }
                }
            }

            // ── New timer form ─────────────────────────────────────────────
            NewTimerForm {
                id: newTimerForm
                Layout.fillWidth: true
                clip: true
                Layout.preferredHeight: timerWindow.showingNewForm ? implicitHeight : 0
                opacity: timerWindow.showingNewForm ? 1 : 0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 150 } }
                onStartTimer: (label, mode, targetSecs) => {
                    TimerService.addTimer(label, mode, targetSecs)
                    timerWindow.showingNewForm = false
                }
                onCancel: timerWindow.showingNewForm = false
            }

            // ── Timer cards ───────────────────────────────────────────────
            Repeater {
                model: TimerService.timers
                delegate: TimerCard {
                    required property var model
                    Layout.fillWidth: true
                    timerId:        model.timerId
                    label:          model.label
                    mode:           model.mode
                    targetSeconds:  model.targetSeconds
                    elapsedSeconds: model.elapsedSeconds
                    timerState:     model.timerState
                }
            }

            // ── History divider ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                visible: timerWindow.historyEntries.length > 0
            }

            // ── History header ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                visible: timerWindow.historyEntries.length > 0

                Text {
                    text: "HISTORY"
                    color: Theme.on_surface_variant
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    font.family: "JetBrainsMono Nerd Font"
                    Layout.fillWidth: true
                }

                Text {
                    text: timerWindow.historyEntries.length + " entries · open file"
                    color: Theme.primary
                    font.pixelSize: 9
                    font.family: "JetBrainsMono Nerd Font"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fileOpener.running = true
                    }
                }
            }

            // ── History rows (up to 10 most recent) ───────────────────────
            Repeater {
                model: Math.min(timerWindow.historyEntries.length, 10)
                delegate: RowLayout {
                    required property int index
                    Layout.fillWidth: true

                    Text {
                        text: timerWindow.historyEntries[index].label
                        color: Theme.on_surface_variant
                        font.pixelSize: 10
                        font.family: "JetBrainsMono Nerd Font"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: timerWindow.historyEntries[index].duration
                        color: Theme.on_surface_variant
                        font.pixelSize: 10
                        font.family: "JetBrainsMono Nerd Font"
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
