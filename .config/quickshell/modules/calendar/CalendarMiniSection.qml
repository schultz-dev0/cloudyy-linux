pragma ComponentBehavior: Bound

// modules/calendar/CalendarMiniSection.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: root

    implicitHeight: innerCol.implicitHeight + 24
    radius: 16
    color: Theme.surface_container
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.22)
    border.width: 1

    ElevatedEffect { target: root }

    readonly property var _upcoming: CalendarService.upcomingEvents(3)

    function _tagColor(tag) {
        return tag === "secondary" ? Theme.secondary
             : tag === "tertiary"  ? Theme.tertiary
             : tag === "error"     ? Theme.error
             : Theme.primary
    }

    ColumnLayout {
        id: innerCol
        anchors { fill: parent; margins: 12 }
        spacing: 8

        // ── Today header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "󰃭"
                color: Theme.primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
            }

            Text {
                text: Qt.formatDate(new Date(), "dddd d MMMM")
                color: Theme.on_surface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.weight: Font.Medium
                Layout.fillWidth: true
            }

            Text {
                text: Qt.formatDate(new Date(), "yyyy")
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
        }

        // ── Upcoming events ───────────────────────────────────────────────────
        Repeater {
            model: root._upcoming
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                // Color dot
                Rectangle {
                    width: 7; height: 7; radius: 4
                    color: root._tagColor(modelData.color || "primary")
                }

                // Title
                Text {
                    text: modelData.title || "Untitled"
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Date/time label
                Text {
                    text: {
                        const label = CalendarService.friendlyDate(modelData.date)
                        const time  = modelData.allDay ? "" : (modelData.startTime || "")
                        return time ? label + " " + time : label
                    }
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        Text {
            visible: root._upcoming.length === 0
            text: "No upcoming events"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
