pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: form

    signal startTimer(string label, string mode, int targetSeconds)
    signal cancel()

    property string selectedMode: "stopwatch"
    property int    hours:   0
    property int    minutes: 0

    implicitHeight: formCol.implicitHeight + 24
    radius: 10
    color: Qt.rgba(Theme.surface_container_high.r,
                   Theme.surface_container_high.g,
                   Theme.surface_container_high.b, 0.5)

    ColumnLayout {
        id: formCol
        anchors {
            top: parent.top; left: parent.left; right: parent.right
            margins: 12
        }
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "New Timer"
                color: Theme.on_surface
                font.pixelSize: 13
                font.weight: Font.Bold
                font.family: "JetBrainsMono Nerd Font"
                Layout.fillWidth: true
            }
            Text {
                text: "✕ Cancel"
                color: Theme.on_surface_variant
                font.pixelSize: 10
                font.family: "JetBrainsMono Nerd Font"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: form.cancel()
                }
            }
        }

        // ── Label input ───────────────────────────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "PROJECT / LABEL"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
                font.family: "JetBrainsMono Nerd Font"
            }
            Rectangle {
                width: parent.width; height: 32
                radius: 8
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                border.color: labelField.activeFocus
                              ? Theme.primary
                              : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.5)
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextInput {
                    id: labelField
                    anchors { fill: parent; margins: 8 }
                    color: Theme.on_surface
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                    clip: true
                    Keys.onReturnPressed: if (text.trim().length > 0) form.submitTimer()

                    Text {
                        visible: labelField.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "..."
                        color: Theme.on_surface_variant
                        font.pixelSize: 12
                        font.family: "JetBrainsMono Nerd Font"
                    }
                }
            }
        }

        // ── Mode toggle ───────────────────────────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "MODE"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
                font.family: "JetBrainsMono Nerd Font"
            }
            Rectangle {
                width: parent.width; height: 30
                radius: 8
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)

                Row {
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        radius: 8
                        color: form.selectedMode === "stopwatch"
                               ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.9)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: "⏱ Stopwatch"
                            color: form.selectedMode === "stopwatch"
                                   ? Theme.on_primary_container : Theme.on_surface_variant
                            font.pixelSize: 11
                            font.family: "JetBrainsMono Nerd Font"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: form.selectedMode = "stopwatch"
                        }
                    }

                    Rectangle {
                        width: parent.width / 2; height: parent.height
                        radius: 8
                        color: form.selectedMode === "countdown"
                               ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g, Theme.primary_container.b, 0.9)
                               : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: "⏳ Countdown"
                            color: form.selectedMode === "countdown"
                                   ? Theme.on_primary_container : Theme.on_surface_variant
                            font.pixelSize: 11
                            font.family: "JetBrainsMono Nerd Font"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: form.selectedMode = "countdown"
                        }
                    }
                }
            }
        }

        // ── Duration picker (countdown only) ──────────────────────────────
        Column {
            Layout.fillWidth: true
            spacing: 4
            opacity: form.selectedMode === "countdown" ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Text {
                text: "DURATION"
                color: Theme.on_surface_variant
                font.pixelSize: 9
                font.weight: Font.Medium
                font.family: "JetBrainsMono Nerd Font"
            }
            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2; height: 32
                    radius: 8
                    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        TextInput {
                            id: hoursField
                            width: 28
                            text: "0"
                            color: Theme.on_surface
                            font.pixelSize: 13
                            font.family: "JetBrainsMono Nerd Font"
                            horizontalAlignment: TextInput.AlignRight
                            validator: IntValidator { bottom: 0; top: 23 }
                            enabled: form.selectedMode === "countdown"
                            onTextChanged: form.hours = parseInt(text) || 0
                        }
                        Text { text: "h"; color: Theme.on_surface_variant; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2; height: 32
                    radius: 8
                    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        TextInput {
                            id: minutesField
                            width: 28
                            text: "00"
                            color: Theme.on_surface
                            font.pixelSize: 13
                            font.family: "JetBrainsMono Nerd Font"
                            horizontalAlignment: TextInput.AlignRight
                            validator: IntValidator { bottom: 0; top: 59 }
                            enabled: form.selectedMode === "countdown"
                            onTextChanged: form.minutes = parseInt(text) || 0
                        }
                        Text { text: "m"; color: Theme.on_surface_variant; font.pixelSize: 12; font.family: "JetBrainsMono Nerd Font" }
                    }
                }
            }
        }

        // ── Start button ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 34
            radius: 10
            color: labelField.text.trim().length > 0
                   ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                   : Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g,
                             Theme.surface_container_high.b, 0.6)
            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                anchors.centerIn: parent
                text:  "▶  Start Timer"
                color: labelField.text.trim().length > 0 ? Theme.on_primary : Theme.on_surface_variant
                font.pixelSize: 12
                font.weight: Font.Bold
                font.family: "JetBrainsMono Nerd Font"
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape:  labelField.text.trim().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled:      labelField.text.trim().length > 0
                onClicked:    form.submitTimer()
            }
        }
    }

    function activate() {
        labelField.forceActiveFocus()
    }

    function submitTimer() {
        const lbl = labelField.text.trim()
        if (lbl.length === 0) return
        const targetSecs = form.selectedMode === "countdown"
                           ? (form.hours * 3600 + form.minutes * 60)
                           : 0
        if (form.selectedMode === "countdown" && targetSecs === 0) return
        form.startTimer(lbl, form.selectedMode, targetSecs)
        labelField.text = ""
        form.selectedMode = "stopwatch"
        form.hours = 0
        form.minutes = 0
        hoursField.text = "0"
        minutesField.text = "00"
    }
}
