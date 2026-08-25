pragma ComponentBehavior: Bound

// modules/calendar/CalendarEventCard.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property var event: null
    signal editRequested(var event)
    signal deleteRequested(string id)

    implicitHeight: cardContent.implicitHeight + 16
    activeFocusOnTab: true

    Rectangle {
        anchors.fill: parent
        color: root.activeFocus ? Theme.islandHover : "transparent"
    }

    Rectangle {
        id: rowRule
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: root.activeFocus ? Theme.islandFocus : Theme.islandBorder
    }

    function _openMenu() {
        ctxMenu.currentIndex = 0;
        ctxMenu.open();
        root.forceActiveFocus();
    }

    function _activateMenuItem() {
        if (ctxMenu.currentIndex === 0) {
            ctxMenu.close();
            root.editRequested(root.event);
        } else if (root.event) {
            ctxMenu.close();
            root.deleteRequested(root.event.id);
        }
    }

    Keys.onReturnPressed: event => {
        if (ctxMenu.visible)
            root._activateMenuItem();
        else
            root._openMenu();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        if (ctxMenu.visible)
            root._activateMenuItem();
        else
            root._openMenu();
        event.accepted = true;
    }
    Keys.onSpacePressed: event => {
        if (ctxMenu.visible)
            root._activateMenuItem();
        else
            root._openMenu();
        event.accepted = true;
    }
    Keys.onUpPressed: event => {
        if (!ctxMenu.visible)
            return;
        ctxMenu.currentIndex = 0;
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        if (!ctxMenu.visible)
            return;
        ctxMenu.currentIndex = 1;
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        if (!ctxMenu.visible)
            return;
        ctxMenu.close();
        event.accepted = true;
    }

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
        // tagColor() follows the live theme and can be near-black in light
        // mode; clamp so the strip stays visible on the island's fixed-black
        // surface (the ctxMenu below sits on its own theme-following
        // background, so it doesn't need this).
        color: Theme._minLightness(
            root.event ? CalendarService.tagColor(root.event.color || "primary") : Theme.islandAccent,
            0.55)
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
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Medium
            renderType: Text.NativeRendering
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
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.event && root.event.allDay
            text: "All day"
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            renderType: Text.NativeRendering
        }

        Text {
            visible: root.event && !!root.event.description
            text: root.event ? (root.event.description || "") : ""
            color: Theme.islandOnSurfaceVariant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            Layout.fillWidth: true
            maximumLineCount: 2
            wrapMode: Text.WordWrap
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        enabled: !ctxMenu.visible
        onClicked: root._openMenu()
    }

    // ── Context menu ──────────────────────────────────────────────────────────
    Rectangle {
        id: ctxMenu
        property int currentIndex: 0
        parent: root.parent ? root.parent : root
        visible: false
        z: 20
        width: 120
        height: 76
        x: root.mapToItem(parent, root.width - width - 4, 4).x
        y: root.mapToItem(parent, root.width - width - 4, 4).y
        radius: 10
        color: Theme.surfaceOverlay
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.5)
        border.width: 1

        function open() { ctxMenu.visible = true }
        function close() { ctxMenu.visible = false }

        ColumnLayout {
            anchors { fill: parent; margins: 6 }
            spacing: 2

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 6
                color: editHover.containsMouse || ctxMenu.currentIndex === 0
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                    : "transparent"

                RowLayout {
                    anchors { fill: parent; leftMargin: 8 }
                    spacing: 6

                    Text {
                        text: "󰏫"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: "Edit"
                        color: Theme.islandOnSurface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
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
                color: delHover.containsMouse || ctxMenu.currentIndex === 1
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
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: "Delete"
                        color: Theme.error
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
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

    }

    // Dismiss context menu on outside click in the menu's stacking context.
    MouseArea {
        id: menuDismissLayer
        parent: root.parent ? root.parent : root
        anchors.fill: parent
        visible: ctxMenu.visible
        z: 19
        onClicked: ctxMenu.close()
    }
}
