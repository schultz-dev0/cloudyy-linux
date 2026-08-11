pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../calendar" as QuickCalendar
import "." as QuickIsland

Item {
    id: root

    signal activateRequested
    property alias expandedContent: expandedSlot.data
    property date currentDate: new Date()

    readonly property var upcoming: {
        const currentDate = root.currentDate;
        return QuickCalendar.CalendarService.upcomingEvents(1);
    }
    readonly property var nextEvent: upcoming.length > 0 ? upcoming[0] : null
    readonly property bool detailVisible: QuickIsland.IslandState.expanded
        && QuickIsland.IslandState.currentPage === "calendar"

    function dateAtOffset(offset) {
        const date = new Date(root.currentDate.getTime());
        date.setDate(date.getDate() + offset);
        return date;
    }

    function focusInitial() {
        if (detailVisible)
            calendarContent.focusInitial();
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
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
                spacing: 5

                Text {
                    width: parent.width
                    text: "Calendar"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: Qt.formatDate(root.currentDate, "dddd, MMMM d")
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: Qt.formatTime(root.currentDate, "HH:mm")
                    color: Theme.islandAccent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 5

                Text {
                    width: parent.width
                    text: root.nextEvent ? root.nextEvent.title : "No upcoming events"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: root.nextEvent
                        ? QuickCalendar.CalendarService.friendlyDate(root.nextEvent.date)
                            + (root.nextEvent.allDay || !root.nextEvent.startTime
                                ? "" : " · " + root.nextEvent.startTime)
                        : "Open calendar"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Row {
                    width: parent.width
                    height: 30

                    Repeater {
                        model: 7

                        delegate: Column {
                            id: dayDelegate
                            required property int index
                            readonly property date day: root.dateAtOffset(index)
                            width: parent.width / 7
                            spacing: 1

                            Text {
                                width: parent.width
                                text: Qt.formatDate(dayDelegate.day, "ddd").slice(0, 1)
                                color: dayDelegate.index === 0
                                    ? Theme.islandAccent : Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                renderType: Text.NativeRendering
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Text {
                                width: parent.width
                                text: Qt.formatDate(dayDelegate.day, "d")
                                color: dayDelegate.index === 0
                                    ? Theme.islandAccent : Theme.islandOnSurface
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                font.weight: dayDelegate.index === 0
                                    ? Font.Bold : Font.Normal
                                renderType: Text.NativeRendering
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }
    }

    Item {
        id: expandedSlot
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

        QuickCalendar.CalendarContent {
            id: calendarContent
            anchors.fill: parent
            onCloseNestedRequested: QuickIsland.IslandState.handleEscape()
        }
    }
}
