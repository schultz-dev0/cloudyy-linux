pragma ComponentBehavior: Bound

// modules/timer/NewTimerForm.qml
import QtQuick
import QtQuick.Layouts
import "../.."

FocusScope {
    id: form

    signal startTimer(string label, string mode, int targetSeconds)
    signal cancel()

    property string selectedMode: "stopwatch"
    property int hours: 0
    property int minutes: 0
    readonly property bool canSubmit: labelField.text.trim().length > 0
        && (selectedMode !== "countdown" || hours > 0 || minutes > 0)

    implicitHeight: formCol.implicitHeight

    Keys.onBacktabPressed: event => event.accepted = false

    function activate() {
        labelField.forceActiveFocus();
    }

    function submitTimer() {
        if (!form.canSubmit)
            return;
        const targetSecs = form.selectedMode === "countdown"
            ? form.hours * 3600 + form.minutes * 60 : 0;
        form.startTimer(labelField.text.trim(), form.selectedMode, targetSecs);
        labelField.text = "";
        form.selectedMode = "stopwatch";
        const hoursControl = durationRepeater.itemAt(0);
        const minutesControl = durationRepeater.itemAt(1);
        if (hoursControl)
            hoursControl.resetInput();
        if (minutesControl)
            minutesControl.resetInput();
    }

    ColumnLayout {
        id: formCol
        width: parent.width
        spacing: 10

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "New timer"
                color: Theme.islandOnSurface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                Layout.fillWidth: true
            }

            Rectangle {
                id: cancelButton
                implicitWidth: cancelLabel.implicitWidth + 14
                implicitHeight: 26
                radius: 7
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                border.width: activeFocus ? 2 : 1
                activeFocusOnTab: true

                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: event => { form.cancel(); event.accepted = true; }
                Keys.onEnterPressed: event => { form.cancel(); event.accepted = true; }
                Keys.onSpacePressed: event => { form.cancel(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: form.cancel()
                }
            }
        }

        Text {
            text: "PROJECT / LABEL"
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.weight: Font.Medium
            renderType: Text.NativeRendering
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 7
            color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                Theme.surface_container.b, 0.45)
            border.color: labelField.activeFocus ? Theme.islandFocus : Theme.islandBorder
            border.width: labelField.activeFocus ? 2 : 1

            TextInput {
                id: labelField
                anchors { fill: parent; margins: 8 }
                activeFocusOnTab: true
                color: Theme.islandOnSurface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                renderType: TextInput.NativeRendering
                clip: true
                verticalAlignment: TextInput.AlignVCenter
                Keys.onReturnPressed: event => {
                    form.submitTimer();
                    event.accepted = form.canSubmit;
                }

                Text {
                    anchors.fill: parent
                    visible: labelField.text.length === 0
                    text: "Name this timer"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            text: "MODE"
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.weight: Font.Medium
            renderType: Text.NativeRendering
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                id: durationRepeater
                model: [
                    { value: "stopwatch", label: "Stopwatch" },
                    { value: "countdown", label: "Countdown" }
                ]

                delegate: Rectangle {
                    id: modeButton
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 7
                    activeFocusOnTab: true
                    color: form.selectedMode === modelData.value
                        ? Qt.rgba(Theme.primary_container.r, Theme.primary_container.g,
                            Theme.primary_container.b, 0.65) : "transparent"
                    border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: activeFocus ? 2 : 1

                    function selectMode() {
                        form.selectedMode = modeButton.modelData.value;
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modeButton.modelData.label
                        color: form.selectedMode === modeButton.modelData.value
                            ? Theme.on_primary_container : Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: event => { modeButton.selectMode(); event.accepted = true; }
                    Keys.onEnterPressed: event => { modeButton.selectMode(); event.accepted = true; }
                    Keys.onSpacePressed: event => { modeButton.selectMode(); event.accepted = true; }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modeButton.selectMode()
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: form.selectedMode === "countdown"
            spacing: 8

            Repeater {
                model: [
                    { suffix: "h", field: "hours" },
                    { suffix: "m", field: "minutes" }
                ]

                delegate: Rectangle {
                    id: durationBox
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 7
                    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                        Theme.surface_container.b, 0.45)
                    border.color: durationInput.activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: durationInput.activeFocus ? 2 : 1

                    function resetInput() {
                        durationInput.text = durationBox.index === 0 ? "0" : "00";
                    }

                    TextInput {
                        id: durationInput
                        anchors.centerIn: parent
                        width: 44
                        text: durationBox.index === 0 ? "0" : "00"
                        activeFocusOnTab: durationBox.visible
                        color: Theme.islandOnSurface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        renderType: TextInput.NativeRendering
                        horizontalAlignment: TextInput.AlignHCenter
                        validator: IntValidator {
                            bottom: 0
                            top: durationBox.index === 0 ? 23 : 59
                        }
                        onTextChanged: {
                            if (durationBox.index === 0)
                                form.hours = parseInt(text, 10) || 0;
                            else
                                form.minutes = parseInt(text, 10) || 0;
                        }
                    }

                    Text {
                        anchors {
                            left: durationInput.right
                            leftMargin: 2
                            verticalCenter: parent.verticalCenter
                        }
                        text: durationBox.modelData.suffix
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Rectangle {
            id: startButton
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 8
            activeFocusOnTab: true
            color: form.canSubmit ? Theme.primary
                : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                    Theme.surface_container.b, 0.45)
            border.color: activeFocus ? Theme.islandFocus : "transparent"
            border.width: activeFocus ? 2 : 0

            Text {
                anchors.centerIn: parent
                text: "Start timer"
                color: form.canSubmit ? Theme.on_primary : Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
            }

            Keys.onReturnPressed: event => { form.submitTimer(); event.accepted = true; }
            Keys.onEnterPressed: event => { form.submitTimer(); event.accepted = true; }
            Keys.onSpacePressed: event => { form.submitTimer(); event.accepted = true; }
            MouseArea {
                anchors.fill: parent
                enabled: form.canSubmit
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: form.submitTimer()
            }
        }
    }
}
