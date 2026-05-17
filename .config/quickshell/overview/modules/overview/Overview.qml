import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../services"
import "."

Scope {
    id: overviewScope
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            property bool blurEnabled: Config.options.overview.effects.enableBlur
            property bool backdropEnabled: Config.options.overview.effects.enableBackdrop
            property real backdropOpacity: Math.max(0, Math.min(1, Config.options.overview.effects.backdropOpacity))
            property bool closeOnFocusLoss: Config.options.overview.closeOnFocusLoss ?? true
            property string tabSelectedAddress: ""
            property string focusedSpecialWorkspace: ""
            screen: modelData
            visible: GlobalStates.overviewOpen

            WlrLayershell.namespace: blurEnabled ? "quickshell:overview-blur" : "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.overviewOpen
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None
            color: "transparent"

            // Only cover the screen while open — full-screen anchors when closed still
            // leave an Overlay input region that steals dock drags/releases.
            anchors {
                top: GlobalStates.overviewOpen
                bottom: GlobalStates.overviewOpen
                left: GlobalStates.overviewOpen
                right: GlobalStates.overviewOpen
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    // Only the monitor that owns the grab may close the overview
                    if (root.closeOnFocusLoss && !active && canBeActive)
                        GlobalStates.overviewOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen) {
                        root.tabSelectedAddress = "";
                        root.focusedSpecialWorkspace = "";
                        delayedGrabTimer.start();
                        Qt.callLater(() => keyHandler.forceActiveFocus());
                    } else {
                        root.focusedSpecialWorkspace = "";
                        grab.active = false;
                    }
                }
            }

            // Re-evaluate grab ownership when focused monitor changes
            Connections {
                target: Hyprland
                function onFocusedMonitorChanged() {
                    if (!GlobalStates.overviewOpen)
                        return;
                    if (root.monitorIsFocused && !grab.active) {
                        grab.active = true;
                    } else if (!root.monitorIsFocused && grab.active) {
                        grab.active = false;
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive)
                        return;
                    grab.active = GlobalStates.overviewOpen;
                    if (GlobalStates.overviewOpen)
                        Qt.callLater(() => keyHandler.forceActiveFocus());
                }
            }

            // Keep the layershell surface full-screen so backdrop/blur are not constrained by content size.
            implicitWidth: screen.width
            implicitHeight: screen.height

            FocusScope {
                id: keyHandler
                anchors.fill: parent
                visible: GlobalStates.overviewOpen
                focus: GlobalStates.overviewOpen
                activeFocusOnTab: true
                z: 0

                Rectangle {
                    id: backdropLayer
                    anchors.fill: parent
                    visible: root.backdropEnabled
                    color: "#000000"
                    opacity: root.backdropOpacity
                    z: 0
                }

                MouseArea {
                    id: outsideClickCatcher
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    enabled: root.closeOnFocusLoss && GlobalStates.overviewOpen
                    propagateComposedEvents: true
                    z: 0
                    onClicked: mouse => {
                        const target = keyHandler.childAt(mouse.x, mouse.y);
                        const clickInsideOverview = target && target !== outsideClickCatcher && target !== backdropLayer;
                        if (clickInsideOverview) {
                            mouse.accepted = false;
                            return;
                        }
                        GlobalStates.overviewOpen = false;
                        mouse.accepted = true;
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return) {
                        if (event.key === Qt.Key_Return && root.focusedSpecialWorkspace !== "")
                            Hyprland.dispatch("togglespecialworkspace " + root.focusedSpecialWorkspace)
                        GlobalStates.overviewOpen = false
                        event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Tab) {
                        const wins = HyprlandData.windowList
                            .filter(w => !(w?.workspace?.name ?? "").startsWith("special:"))
                            .sort((a, b) => (a.focusHistoryID ?? 9999) - (b.focusHistoryID ?? 9999))
                        if (wins.length > 0) {
                            const dir = (event.modifiers & Qt.ShiftModifier) ? 1 : -1
                            let idx = wins.findIndex(w => w.address === root.tabSelectedAddress)
                            if (idx === -1) idx = dir === -1 ? Math.max(wins.length - 2, 0) : 1
                            else idx = ((idx + dir) + wins.length) % wins.length
                            root.tabSelectedAddress = wins[idx].address
                            Hyprland.dispatch("focuswindow address:" + wins[idx].address)
                        }
                        event.accepted = true
                        return
                    }

                    const visibleIds = overviewLoader.item?.visibleWorkspaceIds ?? []
                    const specials   = overviewLoader.item?.visibleSpecialWorkspaces ?? []
                    const currentId  = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
                    const currentIdx = visibleIds.indexOf(currentId)

                    if (root.focusedSpecialWorkspace !== "") {
                        const sIdx = Math.max(0, specials.indexOf(root.focusedSpecialWorkspace))
                        if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
                            root.focusedSpecialWorkspace = specials[(sIdx - 1 + specials.length) % specials.length]
                        else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
                            root.focusedSpecialWorkspace = specials[(sIdx + 1) % specials.length]
                        else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                            root.focusedSpecialWorkspace = ""
                        event.accepted = true
                        return
                    }

                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        if (currentIdx > 0) Hyprland.dispatch("workspace " + visibleIds[currentIdx - 1])
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        if (currentIdx >= 0 && currentIdx < visibleIds.length - 1)
                            Hyprland.dispatch("workspace " + visibleIds[currentIdx + 1])
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        if (specials.length > 0) root.focusedSpecialWorkspace = specials[0]
                    } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        Hyprland.dispatch("workspace " + (event.key - Qt.Key_0))
                    } else if (event.key === Qt.Key_0) {
                        Hyprland.dispatch("workspace 10")
                    }

                    event.accepted = true
                }

                ColumnLayout {
                    id: columnLayout
                    visible: GlobalStates.overviewOpen
                    z: 1
                    width: implicitWidth
                    height: implicitHeight
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: Config.options.position.topMargin
                    }

                    Loader {
                        id: overviewLoader
                        active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                        sourceComponent: OverviewWidget {
                            panelWindow: root
                            visible: true
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overview"

        function togglefloating() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
    }
}
