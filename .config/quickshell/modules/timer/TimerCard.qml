pragma ComponentBehavior: Bound

// modules/timer/TimerCard.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: card

    required property string timerId
    required property string label
    required property string mode
    required property int targetSeconds
    required property int elapsedSeconds
    required property string timerState

    property bool editing: false
    property bool confirmingDismiss: false

    readonly property bool isCountdown: mode === "countdown"
    readonly property int displaySecs: isCountdown
        ? Math.max(0, targetSeconds - elapsedSeconds) : elapsedSeconds
    readonly property bool isWarning: isCountdown && displaySecs < 300
        && timerState === "running"
    readonly property double progress: isCountdown && targetSeconds > 0
        ? Math.max(0, 1 - elapsedSeconds / targetSeconds) : 0

    implicitHeight: cardCol.implicitHeight + 12

    function focusInitial() {
        pauseButton.forceActiveFocus();
    }

    function toggleRunning() {
        if (card.timerState === "running")
            TimerService.pauseTimer(card.timerId);
        else
            TimerService.resumeTimer(card.timerId);
    }

    function requestDismiss() {
        if (card.elapsedSeconds > 0 && !card.confirmingDismiss)
            card.confirmingDismiss = true;
        else
            TimerService.dismissTimer(card.timerId);
    }

    ColumnLayout {
        id: cardCol
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 5

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: (card.timerState === "running" ? "RUNNING" : "PAUSED")
                    + " · " + (card.isCountdown ? "COUNTDOWN" : "STOPWATCH")
                color: card.timerState === "running" ? Theme.islandAccent : Theme.islandAccentAlt
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Medium
                renderType: Text.NativeRendering
                Layout.fillWidth: true
            }

            Rectangle {
                id: editButton
                implicitWidth: 27
                implicitHeight: 24
                radius: 6
                visible: !card.confirmingDismiss
                activeFocusOnTab: visible
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "󰏫"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                function activate() {
                    card.editing = true;
                    Qt.callLater(() => editField.forceActiveFocus());
                }
                Keys.onReturnPressed: event => { editButton.activate(); event.accepted = true; }
                Keys.onEnterPressed: event => { editButton.activate(); event.accepted = true; }
                Keys.onSpacePressed: event => { editButton.activate(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: editButton.activate()
                }
            }

            Rectangle {
                id: cancelDismissButton
                implicitWidth: cancelDismissLabel.implicitWidth + 12
                implicitHeight: 24
                radius: 6
                visible: card.confirmingDismiss
                activeFocusOnTab: visible
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    id: cancelDismissLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                }

                function activate() { card.confirmingDismiss = false; }
                Keys.onReturnPressed: event => { cancelDismissButton.activate(); event.accepted = true; }
                Keys.onEnterPressed: event => { cancelDismissButton.activate(); event.accepted = true; }
                Keys.onSpacePressed: event => { cancelDismissButton.activate(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cancelDismissButton.activate()
                }
            }

            Rectangle {
                id: dismissButton
                objectName: "timerCardDismiss:" + card.timerId
                implicitWidth: dismissLabel.implicitWidth + 12
                implicitHeight: 24
                radius: 6
                activeFocusOnTab: true
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.error : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    id: dismissLabel
                    anchors.centerIn: parent
                    text: card.confirmingDismiss ? "Dismiss?" : "󰅖"
                    color: card.confirmingDismiss ? Theme.error : Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: card.confirmingDismiss ? Font.DemiBold : Font.Normal
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: event => { card.requestDismiss(); event.accepted = true; }
                Keys.onEnterPressed: event => { card.requestDismiss(); event.accepted = true; }
                Keys.onSpacePressed: event => { card.requestDismiss(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.requestDismiss()
                }
            }
        }

        Text {
            visible: !card.editing
            text: card.label
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        TextInput {
            id: editField
            visible: card.editing
            activeFocusOnTab: visible
            text: card.label
            color: Theme.islandOnSurface
            selectionColor: Theme.islandAccent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            renderType: TextInput.NativeRendering
            Layout.fillWidth: true
            Keys.onReturnPressed: event => {
                const nextLabel = text.trim();
                if (nextLabel)
                    TimerService.renameTimer(card.timerId, nextLabel);
                card.editing = false;
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                text = card.label;
                card.editing = false;
                event.accepted = true;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7

            Text {
                text: TimerService.fmtTime(card.displaySecs)
                color: card.isWarning ? Theme.error : Theme.islandOnSurface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 21
                font.weight: Font.Bold
                renderType: Text.NativeRendering
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                id: resetButton
                implicitWidth: 30
                implicitHeight: 25
                radius: 6
                activeFocusOnTab: true
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "󰑐"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                function activate() { TimerService.resetTimer(card.timerId); }
                Keys.onReturnPressed: event => { resetButton.activate(); event.accepted = true; }
                Keys.onEnterPressed: event => { resetButton.activate(); event.accepted = true; }
                Keys.onSpacePressed: event => { resetButton.activate(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: resetButton.activate()
                }
            }

            Rectangle {
                id: pauseButton
                objectName: "timerCardPause:" + card.timerId
                implicitWidth: 30
                implicitHeight: 25
                radius: 6
                activeFocusOnTab: true
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: card.timerState === "running" ? "󰏤" : "󰐊"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: event => { card.toggleRunning(); event.accepted = true; }
                Keys.onEnterPressed: event => { card.toggleRunning(); event.accepted = true; }
                Keys.onSpacePressed: event => { card.toggleRunning(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.toggleRunning()
                }
            }

            Rectangle {
                id: stopButton
                objectName: "timerCardStop:" + card.timerId
                implicitWidth: 30
                implicitHeight: 25
                radius: 6
                activeFocusOnTab: true
                color: activeFocus ? Theme.islandFocus : "transparent"
                border.color: activeFocus ? Theme.error : Theme.islandBorder
                border.width: activeFocus ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "󰓛"
                    color: Theme.error
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                function activate() { TimerService.stopTimer(card.timerId); }
                Keys.onReturnPressed: event => { stopButton.activate(); event.accepted = true; }
                Keys.onEnterPressed: event => { stopButton.activate(); event.accepted = true; }
                Keys.onSpacePressed: event => { stopButton.activate(); event.accepted = true; }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: stopButton.activate()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: card.isCountdown
            implicitHeight: 3
            radius: 2
            color: Qt.rgba(Theme.surface_container_high.r,
                Theme.surface_container_high.g, Theme.surface_container_high.b, 0.5)

            Rectangle {
                width: parent.width * card.progress
                height: parent.height
                radius: parent.radius
                color: card.isWarning ? Theme.error : Theme.islandAccent
            }
        }

        Rectangle {
            id: rowRule
            Layout.fillWidth: true
            Layout.topMargin: 5
            implicitHeight: 1
            color: card.activeFocus ? Theme.islandFocus : Theme.islandBorder
        }
    }
}
