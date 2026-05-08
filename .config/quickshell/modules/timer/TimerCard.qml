pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: card

    // ── Input properties ──────────────────────────────────────────────────
    required property string timerId
    required property string label
    required property string mode
    required property int    targetSeconds
    required property int    elapsedSeconds
    required property string timerState

    // ── Local state ───────────────────────────────────────────────────────
    property bool editing:           false
    property bool confirmingDismiss: false

    // ── Computed ──────────────────────────────────────────────────────────
    readonly property bool   isCountdown: mode === "countdown"
    readonly property int    displaySecs: isCountdown
                                          ? Math.max(0, targetSeconds - elapsedSeconds)
                                          : elapsedSeconds
    readonly property bool   isWarning:   isCountdown && displaySecs < 300 && timerState === "running"
    readonly property double progress:    (isCountdown && targetSeconds > 0)
                                          ? Math.max(0, 1.0 - elapsedSeconds / targetSeconds)
                                          : 0

    implicitHeight: cardCol.implicitHeight + 20
    radius: 10
    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.7)

    // Colored left accent border
    Rectangle {
        width: 3
        height: parent.height
        anchors { left: parent.left; top: parent.top }
        radius: 2
        color: timerState === "running" ? Theme.primary : Theme.tertiary
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    ColumnLayout {
        id: cardCol
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            margins: 10
            leftMargin: 14
        }
        spacing: 4

        // ── Status row ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: {
                    const icon  = timerState === "running" ? "▶" : "⏸"
                    const state = timerState === "running" ? "RUNNING" : "PAUSED"
                    const modeLabel = card.isCountdown
                                      ? ("COUNTDOWN " + fmtTime(targetSeconds))
                                      : "STOPWATCH"
                    return icon + " " + state + " · " + modeLabel
                }
                color: timerState === "running" ? Theme.primary : Theme.tertiary
                font.pixelSize: 9
                font.weight: Font.Medium
                font.family: "JetBrainsMono Nerd Font"
                Layout.fillWidth: true
            }

            Row {
                spacing: 4

                // Edit button (hidden while confirming dismiss)
                Text {
                    visible: !card.confirmingDismiss
                    text:    "✏"
                    color:   Theme.on_surface_variant
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            card.editing = !card.editing
                            if (card.editing) editField.forceActiveFocus()
                        }
                    }
                }

                // Cancel confirm
                Text {
                    visible: card.confirmingDismiss
                    text:    "Cancel"
                    color:   Theme.on_surface_variant
                    font.pixelSize: 9
                    font.family: "JetBrainsMono Nerd Font"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    card.confirmingDismiss = false
                    }
                }

                // Dismiss / confirm-dismiss
                Text {
                    text:  card.confirmingDismiss ? "Dismiss?" : "✕"
                    color: card.confirmingDismiss ? Theme.error : Theme.on_surface_variant
                    font.pixelSize:  card.confirmingDismiss ? 10 : 11
                    font.weight:     card.confirmingDismiss ? Font.Bold : Font.Normal
                    font.family: "JetBrainsMono Nerd Font"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (card.elapsedSeconds > 0 && !card.confirmingDismiss) {
                                card.confirmingDismiss = true
                            } else {
                                TimerService.dismissTimer(card.timerId)
                            }
                        }
                    }
                }
            }
        }

        // ── Label (static text or edit field) ─────────────────────────────
        Text {
            visible: !card.editing
            text:    card.label
            color:   Theme.on_surface
            font.pixelSize: 11
            font.family: "JetBrainsMono Nerd Font"
            elide:   Text.ElideRight
            Layout.fillWidth: true
        }

        TextInput {
            id: editField
            visible:    card.editing
            text:       card.label
            color:      Theme.on_surface
            font.pixelSize: 11
            font.family: "JetBrainsMono Nerd Font"
            Layout.fillWidth: true
            Keys.onReturnPressed: {
                TimerService.renameTimer(card.timerId, text)
                card.editing = false
            }
            Keys.onEscapePressed: card.editing = false
        }

        // ── Time display + controls ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text:       fmtTime(card.displaySecs)
                color:      card.isWarning ? Theme.error : Theme.on_surface
                font.pixelSize: 22
                font.family:    "JetBrainsMono Nerd Font"
                font.weight:    Font.Bold
                Behavior on color { ColorAnimation { duration: 300 } }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 6

                // Pause / Resume
                Rectangle {
                    width: 30; height: 24; radius: 6
                    color: Qt.rgba(Theme.surface_container_high.r,
                                   Theme.surface_container_high.g,
                                   Theme.surface_container_high.b, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text:  timerState === "running" ? "⏸" : "▶"
                        color: Theme.on_surface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (timerState === "running")
                                TimerService.pauseTimer(card.timerId)
                            else
                                TimerService.resumeTimer(card.timerId)
                        }
                    }
                }

                // Stop
                Rectangle {
                    width: 30; height: 24; radius: 6
                    color: Qt.rgba(Theme.surface_container_high.r,
                                   Theme.surface_container_high.g,
                                   Theme.surface_container_high.b, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text:  "■"
                        color: Theme.on_surface
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    TimerService.stopTimer(card.timerId)
                    }
                }
            }
        }

        // ── Countdown progress bar ─────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: card.isCountdown
            height:  3
            radius:  2
            color: Qt.rgba(Theme.surface_container_high.r,
                           Theme.surface_container_high.g,
                           Theme.surface_container_high.b, 0.6)

            Rectangle {
                width:  parent.width * card.progress
                height: parent.height
                radius: parent.radius
                color:  card.isWarning ? Theme.error : Theme.primary
                Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.Linear } }
                Behavior on color { ColorAnimation { duration: 300 } }
            }
        }
    }

    function fmtTime(secs) {
        secs = Math.floor(secs)
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const s = secs % 60
        if (h > 0)
            return h + ":" + String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
        return String(m).padStart(2, "0") + ":" + String(s).padStart(2, "0")
    }
}
