pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../timer" as QuickTimer
import "." as QuickIsland

FocusScope {
    id: root

    signal activateRequested

    readonly property var displayTimer: {
        const primary = QuickTimer.TimerService.primaryTimer;
        if (primary)
            return primary;
        const timers = QuickTimer.TimerService.timers;
        let pausedTimer = null;
        for (let i = timers.count - 1; i >= 0; i--) {
            const timer = timers.get(i);
            if (timer.timerState === "running")
                return timer;
            if (!pausedTimer && timer.timerState === "paused")
                pausedTimer = timer;
        }
        return pausedTimer;
    }
    readonly property int displaySeconds: {
        if (!root.displayTimer)
            return 0;
        if (root.displayTimer.mode === "countdown")
            return Math.max(0, root.displayTimer.targetSeconds
                - root.displayTimer.elapsedSeconds);
        return root.displayTimer.elapsedSeconds;
    }
    readonly property bool detailVisible: QuickIsland.IslandState.expanded
        && QuickIsland.IslandState.currentPage === "timer"
    readonly property bool compactActive: QuickIsland.IslandState.currentPage === "timer"
        && !QuickIsland.IslandState.expanded
    property bool _compactFocusRecoveryPending: false

    function focusInitial() {
        if (root.detailVisible)
            timerContent.focusInitial();
        else if (root.displayTimer)
            pauseButton.forceActiveFocus();
        else
            createButton.forceActiveFocus();
    }

    function toggleRunning() {
        if (!root.displayTimer)
            return;
        if (root.displayTimer.timerState === "paused")
            QuickTimer.TimerService.resumeTimer(root.displayTimer.timerId);
        else
            QuickTimer.TimerService.pauseTimer(root.displayTimer.timerId);
    }

    function _compactActionOwnsFocus() {
        return pauseButton.activeFocus
            || compactResetButton.activeFocus
            || stopButton.activeFocus;
    }

    function _scheduleCompactFocusRecovery(timerId) {
        if (root._compactFocusRecoveryPending
                || !root.compactActive
                || !root.displayTimer
                || root.displayTimer.timerId !== timerId
                || !root._compactActionOwnsFocus())
            return;
        root._compactFocusRecoveryPending = true;
        Qt.callLater(() => root._restoreCompactFocus());
    }

    function _restoreCompactFocus() {
        if (!root._compactFocusRecoveryPending)
            return;
        root._compactFocusRecoveryPending = false;
        if (!root.compactActive)
            return;
        root.focusInitial();
    }

    Connections {
        target: QuickTimer.TimerService

        function onTimerAboutToRemove(timerId) {
            if (stopButton.activeFocus)
                root._scheduleCompactFocusRecovery(timerId);
        }

        function onTimerCompleted(timer) {
            root._scheduleCompactFocusRecovery(timer.timerId);
        }
    }

    Connections {
        target: QuickIsland.IslandState

        function onModeChanged() {
            if (root.detailVisible)
                Qt.callLater(() => root.focusInitial());
        }

        function onCurrentPageChanged() {
            if (root.detailVisible)
                Qt.callLater(() => root.focusInitial());
        }
    }

    QuickIsland.IslandPageFrame {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Math.min(parent.height, 112)

        leftContent: Item {
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 12
                spacing: 6

                Text {
                    width: parent.width
                    text: "Timer"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: root.displayTimer ? root.displayTimer.label : "No active timers"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.displayTimer
                        ? (root.displayTimer.timerState === "paused" ? "Paused" : "Running")
                            + " · " + (root.displayTimer.mode === "countdown"
                                ? "Countdown" : "Stopwatch")
                        : "Open to create one"
                    color: Theme.islandAccent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }
            }

            TapHandler { onTapped: root.activateRequested() }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.displayTimer
                        ? QuickTimer.TimerService.fmtTime(root.displaySeconds)
                        : "Create timer"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: root.displayTimer ? 18 : 11
                    font.weight: Font.Bold
                    renderType: Text.NativeRendering
                }

                Row {
                    id: compactActions
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    visible: root.displayTimer !== null

                    Rectangle {
                        id: pauseButton
                        objectName: "timerCompactPause"
                        width: 52
                        height: 25
                        radius: 6
                        activeFocusOnTab: root.compactActive
                        enabled: root.compactActive
                        color: activeFocus ? Theme.islandFocus
                            : (pauseHandler.pressed ? Theme.islandPressed : Theme.islandHover)
                        border.color: activeFocus ? Theme.islandFocus : "transparent"
                        border.width: activeFocus ? 2 : 0

                        Text {
                            anchors.centerIn: parent
                            text: root.displayTimer?.timerState === "paused" ? "Resume" : "Pause"
                            color: Theme.islandOnSurface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            renderType: Text.NativeRendering
                        }

                        Keys.onReturnPressed: event => { root.toggleRunning(); event.accepted = true; }
                        Keys.onEnterPressed: event => { root.toggleRunning(); event.accepted = true; }
                        Keys.onSpacePressed: event => { root.toggleRunning(); event.accepted = true; }
                        TapHandler { id: pauseHandler; onTapped: root.toggleRunning() }
                    }

                    Rectangle {
                        id: compactResetButton
                        objectName: "timerCompactReset"
                        width: 45
                        height: 25
                        radius: 6
                        activeFocusOnTab: root.compactActive
                        enabled: root.compactActive
                        color: activeFocus ? Theme.islandFocus
                            : (resetHandler.pressed ? Theme.islandPressed : Theme.islandHover)
                        border.color: activeFocus ? Theme.islandFocus : "transparent"
                        border.width: activeFocus ? 2 : 0

                        Text {
                            anchors.centerIn: parent
                            text: "Reset"
                            color: Theme.islandOnSurface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            renderType: Text.NativeRendering
                        }

                        function activate() {
                            if (root.displayTimer)
                                QuickTimer.TimerService.resetTimer(root.displayTimer.timerId);
                        }
                        Keys.onReturnPressed: event => { compactResetButton.activate(); event.accepted = true; }
                        Keys.onEnterPressed: event => { compactResetButton.activate(); event.accepted = true; }
                        Keys.onSpacePressed: event => { compactResetButton.activate(); event.accepted = true; }
                        TapHandler { id: resetHandler; onTapped: compactResetButton.activate() }
                    }

                    Rectangle {
                        id: stopButton
                        objectName: "timerCompactStop"
                        width: 42
                        height: 25
                        radius: 6
                        activeFocusOnTab: root.compactActive
                        enabled: root.compactActive
                        color: activeFocus ? Theme.islandFocus
                            : (stopHandler.pressed ? Theme.islandPressed : Theme.islandHover)
                        border.color: activeFocus ? Theme.error : "transparent"
                        border.width: activeFocus ? 2 : 0

                        Text {
                            anchors.centerIn: parent
                            text: "Stop"
                            color: Theme.error
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            renderType: Text.NativeRendering
                        }

                        function activate() {
                            if (root.displayTimer)
                                QuickTimer.TimerService.stopTimer(root.displayTimer.timerId);
                        }
                        Keys.onReturnPressed: event => { stopButton.activate(); event.accepted = true; }
                        Keys.onEnterPressed: event => { stopButton.activate(); event.accepted = true; }
                        Keys.onSpacePressed: event => { stopButton.activate(); event.accepted = true; }
                        TapHandler { id: stopHandler; onTapped: stopButton.activate() }
                    }
                }

                Rectangle {
                    id: createButton
                    objectName: "timerCompactCreate"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.displayTimer === null
                    width: 92
                    height: 27
                    radius: 7
                    activeFocusOnTab: root.compactActive
                    enabled: root.compactActive
                    color: activeFocus ? Theme.primary : Theme.islandHover
                    border.color: activeFocus ? Theme.islandFocus : Theme.islandBorder
                    border.width: activeFocus ? 2 : 1

                    Text {
                        anchors.centerIn: parent
                        text: "+ New timer"
                        color: createButton.activeFocus ? Theme.on_primary : Theme.islandOnSurface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }

                    // Expanding to the generic Timer overview just to make
                    // the user press a second "+ New timer" there was
                    // pointless friction — this button should go straight
                    // to the input form. timerContent always exists (it's
                    // only visible:false, not Loader-created), so it's
                    // safe to prime showingNewForm before/alongside the
                    // expand; TimerContent.focusInitial() (called via the
                    // IslandState Connections below once detailVisible
                    // flips) already checks showingNewForm and focuses the
                    // form's first field when it's set.
                    function activate() {
                        timerContent.showingNewForm = true;
                        root.activateRequested();
                    }
                    Keys.onReturnPressed: event => { createButton.activate(); event.accepted = true; }
                    Keys.onEnterPressed: event => { createButton.activate(); event.accepted = true; }
                    Keys.onSpacePressed: event => { createButton.activate(); event.accepted = true; }
                    TapHandler { onTapped: createButton.activate() }
                }
            }
        }
    }

    Item {
        anchors {
            top: parent.top
            topMargin: 120
            left: parent.left
            leftMargin: 22
            right: parent.right
            rightMargin: 22
            bottom: parent.bottom
        }
        visible: root.detailVisible
        enabled: visible

        QuickTimer.TimerContent {
            id: timerContent
            anchors.fill: parent
            contentActive: root.detailVisible
            onCloseNestedRequested: QuickIsland.IslandState.handleEscape()
        }
    }
}
