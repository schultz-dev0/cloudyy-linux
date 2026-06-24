pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../.."
import "../../spotlight" as QuickSpotlight
import "../../systemmonitor" as QuickSystemMonitor
import "../../battery" as QuickBattery
import "../applibrary" as QuickAppLibrary

PanelWindow {
    id: root

    readonly property var svc: PowerMenuService
    readonly property var mon: QuickSystemMonitor.SystemMonitorService
    readonly property var bat: QuickBattery.BatteryService

    readonly property int panelWidth: {
        const screens = Quickshell.screens;
        const sw = screens.length > 0 ? screens[0].width : 1920;
        return Math.min(520, Math.round(sw * 0.46));
    }
    readonly property int actionColumns: 5
    readonly property int actionRowHeight: 80
    readonly property int statsHeight: 62
    readonly property int panelContentHeight: 48 + 1 + statsHeight + 36 + actionRowHeight + 10

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    visible: svc.visible
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    MouseArea {
        anchors.fill: parent
        visible: svc.visible
        onClicked: svc.close()
    }

    Item {
        id: panel
        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelContentHeight + 8
        visible: svc.visible

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.glassPanelRadius
            color: Theme.glassShell
            border.color: Theme.glassPanelBorder
            border.width: 1
            antialiasing: true
        }

        FocusScope {
            id: keyNav
            anchors.fill: parent
            anchors.margins: 2
            focus: true

            Keys.onTabPressed: event => {
                root.focusProfiles(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                event.accepted = true;
            }
            Keys.onBacktabPressed: event => {
                root.focusProfiles(-1);
                event.accepted = true;
            }
            Keys.onLeftPressed: event => {
                if (svc.focusZone === "actions")
                    root.moveAction(-1);
                else if (svc.focusZone === "profiles")
                    root.stepProfile(-1);
                event.accepted = true;
            }
            Keys.onRightPressed: event => {
                if (svc.focusZone === "actions")
                    root.moveAction(1);
                else if (svc.focusZone === "profiles")
                    root.stepProfile(1);
                event.accepted = true;
            }
            Keys.onUpPressed: event => {
                if (svc.focusZone === "actions")
                    root.focusProfiles(0);
                event.accepted = true;
            }
            Keys.onDownPressed: event => {
                if (svc.focusZone === "profiles")
                    root.focusActions();
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                root.activateSelection();
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                root.handleEscape();
                event.accepted = true;
            }

            Column {
                id: bodyCol
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 10

                        Text {
                            text: "󰐥"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                            color: Theme.on_surface_variant
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Power"
                            color: Theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 16
                            verticalCenter: parent.verticalCenter
                        }
                        text: mon.stale ? "stats stale" : "live"
                        color: mon.stale ? Theme.error : Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)
                }

                Flickable {
                    id: statsFlick
                    width: parent.width
                    height: root.statsHeight
                    contentWidth: statsRow.width
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: statsRow
                        height: parent.height
                        spacing: 8
                        leftPadding: 14
                        rightPadding: 14

                        PowerStatChip {
                            icon: "󰍛"
                            value: mon.cpuPercent + "%"
                            label: "CPU"
                            detail: mon.cpuTempC > 0 ? mon.cpuTempC + "°C" : mon.cpuAvgPercent + "% avg"
                        }

                        PowerStatChip {
                            icon: "󰘚"
                            value: mon.ramPercent + "%"
                            label: "Memory"
                            detail: mon.ramUsedGb.toFixed(1) + " / " + mon.ramTotalGb.toFixed(1) + " GB"
                        }

                        PowerStatChip {
                            visible: mon.gpuAvailable
                            icon: "󰢮"
                            value: mon.gpuPercent + "%"
                            label: "GPU"
                            detail: mon.gpuTempC > 0 ? mon.gpuTempC + "°C" : (mon.gpuName || "").split(" ")[0]
                        }

                        PowerStatChip {
                            visible: bat.available
                            icon: bat.charging ? "󰂄" : "󰁹"
                            value: Math.round(bat.percent) + "%"
                            label: "Battery"
                            detail: bat.rateEtaLabel
                        }
                    }
                }

                QuickAppLibrary.CategoryPills {
                    id: profilePills
                    width: parent.width
                    labels: svc.profileLabels
                    activeLabel: svc.focusZone === "profiles"
                        ? svc.profileLabels[svc.profileFocusIndex]
                        : svc.profileLabelForId(svc.powerProfile)
                    keyboardFocusIndex: svc.focusZone === "profiles" ? svc.profileFocusIndex : -1
                    onCategorySelected: label => {
                        svc.setProfileByLabel(label);
                        svc.focusZone = "profiles";
                        svc.selectedIndex = -1;
                    }
                }

                Grid {
                    id: actionGrid
                    width: parent.width
                    columns: root.actionColumns
                    rowSpacing: 4
                    columnSpacing: 0
                    topPadding: 8
                    leftPadding: 14
                    rightPadding: 14

                    Repeater {
                        model: svc.actions
                        delegate: PowerActionCell {
                            required property var modelData
                            required property int index
                            icon: modelData.icon
                            label: modelData.label
                            selected: svc.focusZone === "actions" && svc.selectedIndex === index
                            cellWidth: Math.max(1, Math.floor(actionGrid.width / root.actionColumns))
                            onActivated: svc.activateIndex(index)
                        }
                    }
                }
            }
        }
    }

    function stepProfile(delta) {
        svc.focusZone = "profiles";
        svc.selectedIndex = -1;
        let idx = svc.profileFocusIndex;
        if (idx < 0)
            idx = svc.profileIds.indexOf(svc.powerProfile);
        if (idx < 0)
            idx = 0;
        idx = (idx + delta + svc.profileLabels.length) % svc.profileLabels.length;
        svc.selectProfileIndex(idx);
        keyNav.forceActiveFocus();
    }

    function focusProfiles(delta) {
        svc.focusZone = "profiles";
        svc.selectedIndex = -1;
        if (delta === 0) {
            svc.selectProfileIndex(Math.max(0, svc.profileIds.indexOf(svc.powerProfile)));
            keyNav.forceActiveFocus();
            return;
        }
        stepProfile(delta);
    }

    function focusActions() {
        svc.focusZone = "actions";
        if (svc.selectedIndex < 0)
            svc.selectedIndex = 0;
        keyNav.forceActiveFocus();
    }

    function moveAction(delta) {
        const max = svc.actions.length - 1;
        if (max < 0)
            return;
        svc.focusZone = "actions";
        let next = svc.selectedIndex + delta;
        if (next < 0)
            next = 0;
        else if (next > max)
            next = max;
        svc.selectedIndex = next;
    }

    function activateSelection() {
        if (svc.focusZone === "profiles") {
            svc.applyProfileIndex(svc.profileFocusIndex);
            focusActions();
            return;
        }
        if (svc.selectedIndex < 0)
            svc.selectedIndex = 0;
        svc.activateIndex(svc.selectedIndex);
    }

    function handleEscape() {
        const result = svc.escapePressed();
        if (result.commandCenter)
            QuickSpotlight.SpotlightService.restoreFromAppLibrary(result.mode, result.browseStack);
    }

    Connections {
        target: svc
        function onRequestFocus() {
            keyNav.forceActiveFocus();
        }
        function onVisibleChanged() {
            if (svc.visible) {
                mon.restartMonitor();
                Qt.callLater(() => keyNav.forceActiveFocus());
            }
        }
    }

    IpcHandler {
        target: "powermenu"
        function open() { svc.open(); }
        function hide() { svc.close(); }
        function toggle() { svc.toggle(); }
    }
}
