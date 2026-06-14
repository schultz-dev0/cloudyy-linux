pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../../"
import "../../services"

Scope {
    id: root

    property int openedAtMs: 0
    property var activeOverviewWidget: null
    property bool selectNextOnOpen: false

    function open() {
        if (GlobalStates.overviewOpen)
            return;

        openedAtMs = Date.now();
        GlobalStates.overviewOpen = true;
        Hyprland.refreshToplevels();
    }

    function openOrCycle() {
        if (GlobalStates.overviewOpen) {
            root.activeOverviewWidget?.selectNext();
            return;
        }

        root.selectNextOnOpen = true;
        root.open();
    }

    function cyclePrevious() {
        if (GlobalStates.overviewOpen)
            root.activeOverviewWidget?.selectPrevious();
    }

    function close() {
        GlobalStates.overviewOpen = false;
    }

    function toggle() {
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    function resetOverviewSelection() {
        if (root.selectNextOnOpen)
            root.activeOverviewWidget?.resetSelectionToNext();
        else
            root.activeOverviewWidget?.resetSelectionToActive();
    }

    function release() {
        if (!GlobalStates.overviewOpen)
            return;

        if (root.activeOverviewWidget)
            root.activeOverviewWidget.activateSelected();
        else
            close();
    }

    Component {
        id: procProto

        Process {}
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;

        const p = procProto.createObject(root, {
            command: cmd
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function focusWorkspace(workspaceId) {
        // Close before focus so the overlay does not re-mount on the target monitor.
        close();
        focusWorkspaceTimer.workspaceId = workspaceId;
        focusWorkspaceTimer.restart();
    }

    Timer {
        id: focusWorkspaceTimer

        property int workspaceId: -1
        interval: 50
        repeat: false
        onTriggered: HyprDispatch.focusWorkspace(workspaceId);
    }

    function focusWindow(windowData) {
        close();
        focusWindowTimer.windowData = windowData;
        focusWindowTimer.restart();
    }

    Timer {
        id: focusWindowTimer

        property var windowData: null
        interval: 50
        repeat: false
        onTriggered: HyprDispatch.focusWindow(windowData);
    }

    function closeWindow(windowData) {
        HyprDispatch.closeWindowByAddress(windowData?.address);
    }

    function closeWorkspace(workspaceId) {
        const id = Number(workspaceId);
        if (!Number.isFinite(id) || id < 1)
            return;

        const windows = (HyprlandData.windowList ?? []).filter(window => Number(window?.workspace?.id ?? -1) === id);
        for (const window of windows)
            closeWindow(window);
    }

    IpcHandler {
        target: "overview"

        function open() {
            root.openOrCycle();
        }

        function close() {
            root.close();
        }

        function toggle() {
            root.toggle();
        }

        function release() {
            root.release();
        }

        function cyclePrevious() {
            root.cyclePrevious();
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overlay

            required property var modelData
            readonly property var monitorData: Hyprland.monitorFor(modelData)
            readonly property bool isFocusedScreen: monitorData?.id === Hyprland.focusedMonitor?.id

            screen: modelData
            visible: GlobalStates.overviewOpen && isFocusedScreen
            color: "transparent"
            exclusiveZone: 0

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.keyboardFocus: GlobalStates.overviewOpen && isFocusedScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            function focusOverview() {
                if (!GlobalStates.overviewOpen || !overlay.isFocusedScreen)
                    return;

                if (overviewLoader.item) {
                    if (root.selectNextOnOpen) {
                        overviewLoader.item.resetSelectionToNext();
                        root.selectNextOnOpen = false;
                    } else {
                        overviewLoader.item.resetSelectionToActive();
                    }
                }
                focusSurface.forceActiveFocus();
            }

            Rectangle {
                id: focusSurface

                anchors.fill: parent
                color: "transparent"
                focus: GlobalStates.overviewOpen

                Keys.onPressed: event => {
                    const overviewWidget = overviewLoader.item;
                    if (!overviewWidget)
                        return;

                    if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        overviewWidget.selectPrevious();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        overviewWidget.selectNext();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab) {
                        if (Date.now() - root.openedAtMs < 80) {
                            event.accepted = true;
                            return;
                        }
                        if (event.modifiers & Qt.ShiftModifier)
                            overviewWidget.selectPrevious();
                        else
                            overviewWidget.selectNext();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        overviewWidget.activateSelected();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backspace) {
                        overviewWidget.closeSelectedWorkspace();
                        event.accepted = true;
                    } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                        const workspaceId = event.key === Qt.Key_0 ? 10 : event.key - Qt.Key_0;
                        if (overviewWidget.selectWorkspace(workspaceId))
                            overviewWidget.activateSelected();
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: root.close()
                }

                Loader {
                    id: overviewLoader
                    z: 1
                    anchors.fill: parent
                    active: GlobalStates.overviewOpen && overlay.isFocusedScreen
                    sourceComponent: OverviewWidget {
                        screenModel: overlay.modelData
                        monitorData: overlay.monitorData
                        overviewActive: overlay.visible
                        onRequestWorkspace: workspaceId => root.focusWorkspace(workspaceId)
                        onRequestFocusWindow: windowData => root.focusWindow(windowData)
                        onRequestCloseWindow: windowData => root.closeWindow(windowData)
                        onRequestCloseWorkspace: workspaceId => root.closeWorkspace(workspaceId)
                    }
                    onLoaded: {
                        if (overlay.isFocusedScreen)
                            root.activeOverviewWidget = overviewLoader.item;
                        Qt.callLater(() => overlay.focusOverview());
                    }
                }
            }

            Connections {
                target: GlobalStates

                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen)
                        Qt.callLater(() => overlay.focusOverview());
                    else {
                        focusSurface.focus = false;
                        root.activeOverviewWidget = null;
                    }
                }
            }

            onIsFocusedScreenChanged: {
                if (!GlobalStates.overviewOpen)
                    return;
                if (isFocusedScreen && overviewLoader.item)
                    root.activeOverviewWidget = overviewLoader.item;
                if (isFocusedScreen)
                    Qt.callLater(() => overlay.focusOverview());
            }
        }
    }
}
