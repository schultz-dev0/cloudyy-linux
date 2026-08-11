pragma ComponentBehavior: Bound

// modules/timer/TimerContent.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import "../.."

FocusScope {
    id: root

    signal closeNestedRequested

    property bool showingNewForm: false
    property bool historyExpanded: false
    property var historyEntries: []
    property bool contentActive: false
    property date currentDate: new Date()
    readonly property string currentMonth: Qt.formatDate(root.currentDate, "yyyy-MM")
    property int _focusRecoveryIndex: -1
    property bool _focusRecoveryPending: false
    readonly property string _historyFile: TimerService.homeDir
        + "/Desktop/timer_record/" + Qt.formatDate(root.currentDate, "yyyy-MM") + ".md"

    implicitHeight: Math.min(820, timerBody.implicitHeight)
    clip: true

    function focusInitial() {
        if (root.showingNewForm)
            newTimerForm.activate();
        else
            newButton.forceActiveFocus();
    }

    function refreshHistory() {
        if (!root.contentActive)
            return;
        root.historyEntries = [];
        historyReader.running = false;
        historyReader.running = true;
    }

    function openHistoryFile() {
        fileOpener.running = false;
        fileOpener.running = true;
    }

    function _containsFocus(item) {
        const window = root.Window.window;
        let activeItem = window ? window.activeFocusItem : null;
        while (activeItem) {
            if (activeItem === item)
                return true;
            activeItem = activeItem.parent;
        }
        return false;
    }

    function _prepareFocusRecovery(timerId) {
        if (!root.contentActive)
            return;
        for (let i = 0; i < timerRepeater.count; i++) {
            const item = timerRepeater.itemAt(i);
            if (item && item.timerId === timerId && root._containsFocus(item)) {
                root._focusRecoveryIndex = i;
                root._focusRecoveryPending = true;
                return;
            }
        }
    }

    function _restoreFocusAfterRemoval() {
        if (!root._focusRecoveryPending)
            return;
        root._focusRecoveryPending = false;
        if (!root.contentActive)
            return;
        const nextIndex = Math.min(root._focusRecoveryIndex, timerRepeater.count - 1);
        const nextTimer = nextIndex >= 0 ? timerRepeater.itemAt(nextIndex) : null;
        if (nextTimer)
            nextTimer.focusInitial();
        else
            newButton.forceActiveFocus();
    }

    onVisibleChanged: {
        if (visible && contentActive)
            refreshHistory();
    }

    onContentActiveChanged: {
        if (contentActive)
            refreshHistory();
    }

    onCurrentMonthChanged: {
        if (root.contentActive)
            refreshHistory();
    }

    onShowingNewFormChanged: {
        if (showingNewForm)
            Qt.callLater(() => newTimerForm.activate());
        else
            Qt.callLater(() => newButton.forceActiveFocus());
    }

    Keys.onEscapePressed: event => {
        if (root.showingNewForm)
            root.showingNewForm = false;
        else
            root.closeNestedRequested();
        event.accepted = true;
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    Connections {
        target: TimerService

        function onTimerAboutToRemove(timerId) {
            root._prepareFocusRecovery(timerId);
            if (root._focusRecoveryPending)
                Qt.callLater(() => root._restoreFocusAfterRemoval());
        }

        function onHistoryChanged() {
            if (root.contentActive)
                root.refreshHistory();
        }
    }

    Process {
        id: historyReader
        command: ["cat", root._historyFile]
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (!line.startsWith("| ") || line.startsWith("| Started")
                        || line.startsWith("|---"))
                    return;
                const parts = line.split("|").map(part => part.trim())
                    .filter(part => part.length > 0);
                if (parts.length < 3)
                    return;
                root.historyEntries = root.historyEntries.concat([{
                    started: parts[0],
                    label: parts[1],
                    duration: parts[2],
                    mode: parts[3] || ""
                }]);
            }
        }
        onRunningChanged: {
            if (!running)
                root.historyEntries = root.historyEntries.slice().reverse();
        }
    }

    Process {
        id: fileOpener
        command: ["xdg-open", root._historyFile]
        running: false
    }

    Flickable {
        anchors.fill: parent
        contentHeight: timerBody.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
            id: timerBody
            width: parent.width
            spacing: 9

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: TimerService.timers.count > 0
                        ? TimerService.timers.count + " active" : "No timers yet"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    renderType: Text.NativeRendering
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: newButton
                    objectName: "timerNew"
                    implicitWidth: newLabel.implicitWidth + 16
                    implicitHeight: 28
                    radius: 7
                    visible: !root.showingNewForm
                    activeFocusOnTab: visible
                    color: activeFocus ? Theme.primary
                        : Qt.rgba(Theme.primary_container.r, Theme.primary_container.g,
                            Theme.primary_container.b, 0.5)
                    border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: activeFocus ? 2 : 1

                    Text {
                        id: newLabel
                        anchors.centerIn: parent
                        text: "+ New timer"
                        color: newButton.activeFocus ? Theme.on_primary
                            : Theme.on_primary_container
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }

                    function activate() { root.showingNewForm = true; }
                    Keys.onReturnPressed: event => { newButton.activate(); event.accepted = true; }
                    Keys.onEnterPressed: event => { newButton.activate(); event.accepted = true; }
                    Keys.onSpacePressed: event => { newButton.activate(); event.accepted = true; }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newButton.activate()
                    }
                }
            }

            NewTimerForm {
                id: newTimerForm
                Layout.fillWidth: true
                visible: root.showingNewForm
                onStartTimer: (label, mode, targetSeconds) => {
                    TimerService.addTimer(label, mode, targetSeconds);
                    root.showingNewForm = false;
                }
                onCancel: root.showingNewForm = false
            }

            Repeater {
                id: timerRepeater
                model: TimerService.timers

                delegate: TimerCard {
                    required property var model
                    Layout.fillWidth: true
                    timerId: model.timerId
                    label: model.label
                    mode: model.mode
                    targetSeconds: model.targetSeconds
                    elapsedSeconds: model.elapsedSeconds
                    timerState: model.timerState
                }
            }

            Rectangle {
                id: bodyDivider
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 1
                color: Theme.islandBorder
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    id: historyButton
                    implicitWidth: historyLabel.implicitWidth + 14
                    implicitHeight: 27
                    radius: 7
                    activeFocusOnTab: true
                    color: activeFocus ? Theme.islandFocus : "transparent"
                    border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: activeFocus ? 2 : 1

                    Text {
                        id: historyLabel
                        anchors.centerIn: parent
                        text: (root.historyExpanded ? "󰅀 " : "󰅂 ") + "HISTORY"
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }

                    function activate() { root.historyExpanded = !root.historyExpanded; }
                    Keys.onReturnPressed: event => { historyButton.activate(); event.accepted = true; }
                    Keys.onEnterPressed: event => { historyButton.activate(); event.accepted = true; }
                    Keys.onSpacePressed: event => { historyButton.activate(); event.accepted = true; }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: historyButton.activate()
                    }
                }

                Text {
                    text: root.historyEntries.length + " recent"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: openHistoryButton
                    implicitWidth: openHistoryLabel.implicitWidth + 14
                    implicitHeight: 27
                    radius: 7
                    activeFocusOnTab: true
                    color: activeFocus ? Theme.islandFocus : "transparent"
                    border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: activeFocus ? 2 : 1

                    Text {
                        id: openHistoryLabel
                        anchors.centerIn: parent
                        text: "Open file"
                        color: Theme.islandAccent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: event => { root.openHistoryFile(); event.accepted = true; }
                    Keys.onEnterPressed: event => { root.openHistoryFile(); event.accepted = true; }
                    Keys.onSpacePressed: event => { root.openHistoryFile(); event.accepted = true; }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openHistoryFile()
                    }
                }
            }

            Repeater {
                model: root.historyExpanded ? Math.min(root.historyEntries.length, 10) : 0

                delegate: Rectangle {
                    id: historyRow
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 27
                    radius: 5
                    activeFocusOnTab: true
                    color: activeFocus ? Theme.islandFocus : "transparent"
                    border.color: activeFocus ? Theme.islandFocus : "transparent"
                    border.width: activeFocus ? 2 : 0

                    RowLayout {
                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }

                        Text {
                            text: root.historyEntries[historyRow.index].label
                            color: Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.historyEntries[historyRow.index].duration
                            color: Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                        }
                    }

                    Keys.onReturnPressed: event => { root.openHistoryFile(); event.accepted = true; }
                    Keys.onEnterPressed: event => { root.openHistoryFile(); event.accepted = true; }
                    Keys.onSpacePressed: event => { root.openHistoryFile(); event.accepted = true; }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openHistoryFile()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: TimerService.persistenceError !== ""
                text: TimerService.persistenceError
                color: Theme.error
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                renderType: Text.NativeRendering
                wrapMode: Text.WordWrap
            }

            Item { implicitHeight: 2 }
        }
    }

    Component.onCompleted: {
        if (root.contentActive)
            refreshHistory();
    }
}
