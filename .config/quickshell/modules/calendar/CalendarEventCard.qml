pragma ComponentBehavior: Bound

// modules/calendar/CalendarEventCard.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: root

    property var event: null
    signal editRequested(var event)
    signal deleteRequested(string id)

    function _tagColor(tag) {
        return tag === "secondary" ? Theme.secondary
             : tag === "tertiary"  ? Theme.tertiary
             : tag === "error"     ? Theme.error
             : Theme.primary
    }

    implicitHeight: cardContent.implicitHeight + 16
    radius: 10
    color: Theme.surface_container_high
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
    border.width: 1

    // Color tag strip
    Rectangle {
        width: 4
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            topMargin: 4
            bottomMargin: 4
            leftMargin: 4
        }
        radius: 2
        color: root.event ? root._tagColor(root.event.color || "primary") : Theme.primary
    }

    ColumnLayout {
        id: cardContent
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 16
            rightMargin: 12
        }
        spacing: 2

        Text {
            text: root.event ? (root.event.title || "Untitled") : ""
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Text {
            visible: root.event && !root.event.allDay && !!root.event.startTime
            text: {
                if (!root.event || root.event.allDay) return ""
                const s = root.event.startTime || ""
                const e = root.event.endTime   || ""
                return e ? s + " – " + e : s
            }
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
        }

        Text {
            visible: root.event && root.event.allDay
            text: "All day"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
        }

        Text {
            visible: root.event && !!root.event.description
            text: root.event ? (root.event.description || "") : ""
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            elide: Text.ElideRight
            Layout.fillWidth: true
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                ctxMenu.open()
        }
    }

    // ── Context menu ──────────────────────────────────────────────────────────
    Rectangle {
        id: ctxMenu
        visible: false
        z: 20
        width: 120
        height: 76
        radius: 10
        color: Theme.surface_container_highest
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.5)
        border.width: 1
        anchors {
            right: parent.right
            top:   parent.top
            topMargin: 4
            rightMargin: 4
        }

        function open() { ctxMenu.visible = true }
        function close() { ctxMenu.visible = false }

        ElevatedEffect { target: ctxMenu }

        ColumnLayout {
            anchors { fill: parent; margins: 6 }
            spacing: 2

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 6
                color: editHover.containsMouse
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                    : "transparent"

                RowLayout {
                    anchors { fill: parent; leftMargin: 8 }
                    spacing: 6

                    Text {
                        text: "󰏫"
                        color: Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                    }
                    Text {
                        text: "Edit"
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: editHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ctxMenu.close()
                        root.editRequested(root.event)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 6
                color: delHover.containsMouse
                    ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12)
                    : "transparent"

                RowLayout {
                    anchors { fill: parent; leftMargin: 8 }
                    spacing: 6

                    Text {
                        text: "󰩺"
                        color: Theme.error
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                    }
                    Text {
                        text: "Delete"
                        color: Theme.error
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: delHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        ctxMenu.close()
                        if (root.event) root.deleteRequested(root.event.id)
                    }
                }
            }
        }

        // Dismiss context menu on outside click
        MouseArea {
            parent: root.parent ? root.parent : root
            anchors.fill: parent
            visible: ctxMenu.visible
            z: ctxMenu.z - 1
            onClicked: ctxMenu.close()
        }
    }
}
