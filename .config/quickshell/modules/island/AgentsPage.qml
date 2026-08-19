pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "AgentsPolicy.js" as Policy
import "." as QuickIsland

FocusScope {
    id: root

    signal activateRequested

    property string pageView: "providers"
    property string selectedProviderId: ""
    property double presentationTime: Date.now()
    readonly property bool pageActive: QuickIsland.IslandState.currentPage === "agents"
        && QuickIsland.IslandState.mode !== "resting"
    readonly property bool detailActive: QuickIsland.IslandState.expanded
        && QuickIsland.IslandState.currentPage === "agents"
    readonly property var providerRecords: {
        const records = [];
        const usage = QuickIsland.AgentsService.usageRecords;
        for (let i = 0; i < usage.length; i++) {
            if (usage[i].allowances.length > 0)
                records.push(usage[i]);
        }
        return records;
    }
    readonly property var compactRecord: providerRecords.length > 0
        ? providerRecords[0] : null
    readonly property var selectedRecord: {
        for (let i = 0; i < providerRecords.length; i++) {
            if (providerRecords[i].recordId === root.selectedProviderId)
                return providerRecords[i];
        }
        return providerRecords.length > 0 ? providerRecords[0] : null;
    }
    readonly property var compactAllowance: root.compactRecord
        ? Policy.tightestAllowance(root.compactRecord.allowances) : null

    function providerIcon(recordId) {
        if (recordId === "claude")
            return "󰚩";
        if (recordId === "codex")
            return "󰧑";
        if (recordId === "fireworks")
            return "󰈸";
        return "󰚩";
    }

    function _repairSelection() {
        root.selectedProviderId = Policy.repairSelectedProvider(
            root.selectedProviderId, root.providerRecords);
    }

    function showProviders() {
        root.pageView = "providers";
        Qt.callLater(() => root.focusInitial());
    }

    function showSessions() {
        root.pageView = "sessions";
        Qt.callLater(() => root.focusInitial());
    }

    function _enterAgentsPage() {
        root.pageView = "providers";
        root.presentationTime = Date.now();
        Qt.callLater(() => root.focusInitial());
    }

    function focusInitial() {
        if (!root.detailActive)
            return;
        if (root.pageView === "sessions")
            backButton.forceActiveFocus();
        else if (root.providerRecords.length > 0)
            providerTabs.itemAt(0)?.forceActiveFocus();
        else
            sessionsButton.forceActiveFocus();
    }

    Keys.onEscapePressed: event => {
        if (root.pageView === "sessions") {
            root.pageView = "providers";
            Qt.callLater(() => root.focusInitial());
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    Connections {
        target: QuickIsland.AgentsService

        function onUsageRecordsChanged() {
            root._repairSelection();
        }
    }

    Connections {
        target: QuickIsland.IslandState

        function onModeChanged() {
            if (root.pageActive)
                root._enterAgentsPage();
            else
                root.pageView = "providers";
        }

        function onCurrentPageChanged() {
            if (QuickIsland.IslandState.currentPage === "agents"
                    && QuickIsland.IslandState.mode !== "resting")
                root._enterAgentsPage();
            else
                root.pageView = "providers";
        }
    }

    Timer {
        interval: 60000
        running: root.pageActive
        repeat: true
        onTriggered: root.presentationTime = Date.now()
    }

    QuickIsland.IslandPageFrame {
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: Math.min(parent.height, 112)

        leftContent: Item {
            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 12
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38
                    radius: 9
                    color: Theme.islandHover
                    border.width: 1
                    border.color: Theme.islandBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.compactRecord
                            ? root.providerIcon(root.compactRecord.recordId) : "󰚩"
                        color: Theme.islandAccent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 17
                        renderType: Text.NativeRendering
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 48
                    spacing: 4

                    Text {
                        width: parent.width
                        text: root.compactRecord ? root.compactRecord.providerName
                            : QuickIsland.AgentsService.oldestSession?.agentName ?? "Agents"
                        color: Theme.islandOnSurface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.compactRecord
                            ? (root.compactRecord.planLabel || "Usage")
                                + (root.compactRecord.stale ? " · Stale" : "")
                            : QuickIsland.AgentsService.oldestSession?.projectName ?? "No activity"
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                }
            }

            TapHandler { onTapped: root.activateRequested() }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 7

                Text {
                    width: parent.width
                    text: root.compactAllowance ? root.compactAllowance.label
                        : (QuickIsland.AgentsService.oldestSession
                            ? "Running session" : "Usage unavailable")
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.compactAllowance !== null
                    width: parent.width
                    height: 3
                    radius: 2
                    color: Theme.islandBorder

                    Rectangle {
                        width: parent.width * (root.compactAllowance?.usedPercent ?? 0) / 100
                        height: 3
                        radius: 2
                        color: (root.compactAllowance?.usedPercent ?? 0) >= 90
                            ? Theme.error : Theme.islandAccent
                    }
                }

                Text {
                    width: parent.width
                    text: root.compactAllowance
                        ? Math.round(root.compactAllowance.usedPercent) + "% used"
                        : (QuickIsland.AgentsService.oldestSession
                            ? Policy.formatElapsed(QuickIsland.AgentsService.oldestSession.startedAt,
                                root.presentationTime) : "")
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors {
            top: parent.top
            topMargin: 116
            left: parent.left
            leftMargin: 22
            right: parent.right
            rightMargin: 22
            bottom: parent.bottom
        }
        visible: root.detailActive
        enabled: visible
        color: Theme.islandSurface

        Item {
            anchors.fill: parent
            visible: root.pageView === "providers"

            Column {
                anchors.fill: parent
                spacing: 12

                Row {
                    width: parent.width
                    height: 42
                    spacing: 10

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: 9
                        color: Theme.islandHover
                        border.width: 1
                        border.color: Theme.islandBorder

                        Text {
                            anchors.centerIn: parent
                            text: root.selectedRecord
                                ? root.providerIcon(root.selectedRecord.recordId) : "󰚩"
                            color: Theme.islandAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                            renderType: Text.NativeRendering
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 46
                        spacing: 3

                        Text {
                            width: parent.width
                            text: root.selectedRecord ? root.selectedRecord.providerName : "Agents"
                            color: Theme.islandOnSurface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.selectedRecord
                                ? (root.selectedRecord.planLabel || "Usage")
                                    + (root.selectedRecord.stale ? " · Stale" : "")
                                : "No provider usage available"
                            color: root.selectedRecord?.stale
                                ? Theme.error : Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 6

                    Repeater {
                        id: providerTabs
                        model: root.providerRecords

                        delegate: Rectangle {
                            id: providerTab
                            required property var modelData

                            height: 28
                            width: Math.max(72, providerTabLabel.implicitWidth + 20)
                            radius: 7
                            activeFocusOnTab: root.detailActive
                            color: activeFocus ? Theme.islandPressed
                                : modelData.recordId === root.selectedProviderId
                                    ? Theme.islandHover : "transparent"
                            border.width: activeFocus ? 1 : 0
                            border.color: Theme.islandFocus

                            function activate() {
                                root.selectedProviderId = modelData.recordId;
                            }

                            Text {
                                id: providerTabLabel
                                anchors.centerIn: parent
                                text: providerTab.modelData.providerName
                                color: Theme.islandOnSurface
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                renderType: Text.NativeRendering
                            }

                            Keys.onReturnPressed: event => {
                                providerTab.activate();
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: event => {
                                providerTab.activate();
                                event.accepted = true;
                            }
                            TapHandler {
                                id: providerTabTap
                                onTapped: providerTab.activate()
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 13

                    Repeater {
                        model: root.selectedRecord ? root.selectedRecord.allowances : []

                        delegate: Column {
                            id: allowanceRow
                            required property var modelData

                            width: parent.width
                            spacing: 5

                            Row {
                                width: parent.width

                                Text {
                                    width: parent.width - 76
                                    text: allowanceRow.modelData.label
                                    color: Theme.islandOnSurface
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                    renderType: Text.NativeRendering
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: 76
                                    text: Math.round(allowanceRow.modelData.usedPercent) + "% used"
                                    color: allowanceRow.modelData.usedPercent >= 90
                                        ? Theme.error : Theme.islandOnSurfaceVariant
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                    renderType: Text.NativeRendering
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 3
                                radius: 2
                                color: Theme.islandBorder

                                Rectangle {
                                    width: parent.width * allowanceRow.modelData.usedPercent / 100
                                    height: 3
                                    radius: 2
                                    color: allowanceRow.modelData.usedPercent >= 90
                                        ? Theme.error : Theme.islandAccent
                                }
                            }

                            Text {
                                width: parent.width
                                text: Policy.formatReset(allowanceRow.modelData.resetAt,
                                    root.presentationTime)
                                color: Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: sessionsButton
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 34
                radius: 8
                activeFocusOnTab: root.detailActive
                color: activeFocus ? Theme.islandPressed
                    : sessionsTap.pressed ? Theme.islandPressed : Theme.islandHover
                border.width: activeFocus ? 1 : 0
                border.color: Theme.islandFocus

                Text {
                    anchors.centerIn: parent
                    text: "Open sessions ›"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: event => {
                    root.showSessions();
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    root.showSessions();
                    event.accepted = true;
                }
                TapHandler { id: sessionsTap; onTapped: root.showSessions() }
            }
        }

        Item {
            anchors.fill: parent
            visible: root.pageView === "sessions"

            Rectangle {
                id: backButton
                anchors {
                    top: parent.top
                    left: parent.left
                }
                width: 74
                height: 30
                radius: 7
                activeFocusOnTab: root.detailActive
                color: activeFocus ? Theme.islandPressed
                    : backTap.pressed ? Theme.islandPressed : Theme.islandHover
                border.width: activeFocus ? 1 : 0
                border.color: Theme.islandFocus

                Text {
                    anchors.centerIn: parent
                    text: "‹ Back"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: event => {
                    root.showProviders();
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    root.showProviders();
                    event.accepted = true;
                }
                TapHandler { id: backTap; onTapped: root.showProviders() }
            }

            ListView {
                id: sessionsList
                anchors {
                    top: backButton.bottom
                    topMargin: 10
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                activeFocusOnTab: root.detailActive
                keyNavigationEnabled: true
                model: QuickIsland.AgentsService.liveSessions

                Keys.onReturnPressed: event => {
                    if (sessionsList.currentItem)
                        sessionsList.currentItem.activate();
                    event.accepted = true;
                }
                Keys.onEnterPressed: event => {
                    if (sessionsList.currentItem)
                        sessionsList.currentItem.activate();
                    event.accepted = true;
                }

                delegate: Rectangle {
                    id: sessionRow
                    required property int index
                    required property var modelData

                    width: sessionsList.width
                    height: 52
                    color: sessionTap.pressed ? Theme.islandPressed : "transparent"
                    activeFocusOnTab: root.detailActive
                    border.width: 0

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 1
                        color: sessionRow.activeFocus
                            || (sessionsList.activeFocus && sessionRow.ListView.isCurrentItem)
                            ? Theme.islandFocus : Theme.islandBorder
                    }

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                        }
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            text: root.providerIcon(sessionRow.modelData.agentId)
                            color: Theme.islandAccent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            renderType: Text.NativeRendering
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 116
                            spacing: 3

                            Text {
                                width: parent.width
                                text: sessionRow.modelData.agentName + " · "
                                    + (sessionRow.modelData.projectName || "Unknown project")
                                color: Theme.islandOnSurface
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                renderType: Text.NativeRendering
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: sessionRow.modelData.workingDirectory
                                color: Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                renderType: Text.NativeRendering
                                elide: Text.ElideMiddle
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72
                            text: Policy.formatElapsed(sessionRow.modelData.startedAt,
                                root.presentationTime)
                            color: Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            renderType: Text.NativeRendering
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    function activate() {
                        QuickIsland.AgentsService.focusSession(modelData.agentId, modelData.pid, modelData.startedAt);
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            sessionsList.currentIndex = index;
                            sessionsList.positionViewAtIndex(index, ListView.Contain);
                        }
                    }

                    Keys.onReturnPressed: event => {
                        sessionRow.activate();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        sessionRow.activate();
                        event.accepted = true;
                    }
                    TapHandler { id: sessionTap; onTapped: sessionRow.activate() }
                }
            }
        }
    }

    Component.onCompleted: root._repairSelection()
}
