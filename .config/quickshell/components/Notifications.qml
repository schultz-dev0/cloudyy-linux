// cloudyyOS — quickshell notifications & control-center
// Replaces swaync. Same functions: toast popups, slide-in panel,
// 8 quick-action buttons, DND, clear-all, keybind targets.
//
// IPC (call from hyprland binds, replaces swaync-client):
//   qs ipc call notifs toggle        — toggle control center
//   qs ipc call notifs dnd           — toggle DND
//   qs ipc call notifs dismissLast   — dismiss top-most popup
//   qs ipc call notifs clear         — clear all stored notifications
//
// All sizes / radii / spacings / timings come from Style.qml.
// All colors come from Theme.qml (matugen-generated).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import ".."

Scope {
    id: notifs

    property bool dndEnabled: false
    property bool centerOpen: false

    // history (newest first). Items: { id, app, summary, body, image, urgency, time }
    ListModel { id: history }
    // currently-on-screen popups (subset of history while alive)
    ListModel { id: popups }

    // ---- IPC ---------------------------------------------------------------
    IpcHandler {
        target: "notifs"
        function toggle(): void { notifs.centerOpen = !notifs.centerOpen }
        function dnd(): void {
            notifs.dndEnabled = !notifs.dndEnabled
            if (notifs.dndEnabled) popups.clear()
        }
        function dismissLast(): void { if (popups.count > 0) popups.remove(0) }
        function clear(): void { history.clear(); popups.clear() }
    }

    // ---- D-Bus notification server ----------------------------------------
    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true

        onNotification: n => {
            n.tracked = true
            const entry = {
                nid: n.id,
                app: n.appName || "system",
                summary: n.summary || "",
                body: n.body || "",
                image: n.image || "",
                urgency: n.urgency,
                time: Qt.formatDateTime(new Date(), "HH:mm")
            }
            history.insert(0, entry)
            while (history.count > Style.historyMax) history.remove(history.count - 1)
            if (!notifs.dndEnabled) {
                popups.insert(0, entry)
                while (popups.count > Style.popupMaxCount) popups.remove(popups.count - 1)
            }
        }
    }

    // ---- popup overlay (top-right of primary screen) ----------------------
    PanelWindow {
        id: popupWin
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: popups.count > 0
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: Style.popupMarginTop; right: Style.popupMarginRight }
        implicitWidth: Style.popupWidth
        implicitHeight: Math.max(1, popupCol.implicitHeight)
        exclusiveZone: 0

        ColumnLayout {
            id: popupCol
            width: parent.width
            spacing: Style.popupSpacing

            Repeater {
                model: popups
                delegate: NotifCard {
                    Layout.fillWidth: true
                    summary: model.summary
                    body: model.body
                    appName: model.app
                    image: model.image
                    urgency: model.urgency
                    timeText: model.time

                    // auto-dismiss popups (urgency 2 = critical → no auto-dismiss)
                    Timer {
                        interval: Style.popupTimeoutMs
                        running: model.urgency !== 2
                        repeat: false
                        onTriggered: popups.remove(index)
                    }
                    onDismissed: popups.remove(index)
                }
            }
        }
    }

    // ---- control center (slide-in from top-right) -------------------------
    PanelWindow {
        id: centerWin
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: notifs.centerOpen
        color: "transparent"
        anchors { top: true; right: true; bottom: true }
        margins { top: Style.centerMarginTop; right: Style.centerMarginSide; bottom: Style.centerMarginBottom }
        implicitWidth: Style.centerWidth
        exclusiveZone: 0

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Style.centerRadius
            antialiasing: true
            border.width: 1
            border.color: Theme.glassEdge

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(Theme.skyTop.r,    Theme.skyTop.g,    Theme.skyTop.b,    Style.panelGradientTopAlpha) }
                GradientStop { position: 1.0; color: Qt.rgba(Theme.skyBottom.r, Theme.skyBottom.g, Theme.skyBottom.b, Style.panelGradientBotAlpha) }
            }

            // top sheen
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 1
                height: Style.centerSheenHeight
                radius: parent.radius - 1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaTopStrong) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaBottom) }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.centerPadding
                spacing: Style.centerSpacing

                // ---- title bar ----
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Control Center"
                        color: Theme.textPrimary
                        font.pixelSize: Style.centerTitleSize
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    GlossyButton {
                        text: "Clear"
                        onClicked: notifs.clear()
                    }
                }

                // ---- buttons grid ----
                GridLayout {
                    Layout.fillWidth: true
                    columns: Style.quickActionGridCols
                    rowSpacing: Style.quickActionGridSpacing
                    columnSpacing: Style.quickActionGridSpacing

                    QuickAction { label: "󰖩"; tooltip: "Wi-Fi";        action: ["uwsm-app", "--", "nm-connection-editor"] }
                    QuickAction { label: "";  tooltip: "Bluetooth";   action: ["uwsm-app", "--", "blueman-manager"] }
                    QuickAction { label: "󱐋"; tooltip: "Sliders";     action: ["sh", "-c", "uwsm-app -- python3 $HOME/cloudyy_scripts/sliders/cloudyy_sliders.py"] }
                    QuickAction { label: "󰸉"; tooltip: "Appearance";  action: ["sh", "-c", "uwsm-app -- $HOME/cloudyy_scripts/rofi/appearance.sh --select"] }
                    QuickAction { label: "";  tooltip: "Color picker"; action: ["hyprpicker"] }
                    QuickAction { label: "󱩌"; tooltip: "Toggle theme"; action: ["sh", "-c", "$HOME/cloudyy_scripts/theme_controller.sh toggle"] }
                    QuickAction { label: "󰘴"; tooltip: "Cloud Center"; action: ["sh", "-c", "uwsmp-app -- python3 $HOME/cloudyy_scripts/cloud-center-v2/cloud-center.py"] }
                    QuickAction { label: "󰐥"; tooltip: "Power";       action: ["sh", "-c", "uwsm-app -- $HOME/cloudyy_scripts/rofi/power-menu.sh"]; danger: true }
                }

                // ---- DND row ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.dndRowHeight
                    radius: Style.dndRowRadius
                    color: Qt.rgba(1, 1, 1, Style.surfaceAlphaIdle)
                    border.color: Theme.glassEdge
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Style.dndRowPaddingLeft
                        anchors.rightMargin: Style.dndRowPaddingRight

                        Text {
                            text: "󰂛  Do Not Disturb"
                            color: Theme.textPrimary
                            font.pixelSize: Style.dndTextSize
                        }
                        Item { Layout.fillWidth: true }
                        Toggle {
                            checked: notifs.dndEnabled
                            onToggled: notifs.dndEnabled = !notifs.dndEnabled
                        }
                    }
                }

                // ---- notifications history ----
                Text {
                    text: history.count === 0 ? "No notifications" : "Notifications (" + history.count + ")"
                    color: Theme.textMuted
                    font.pixelSize: Style.historyHeaderSize
                    Layout.topMargin: 4
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.historyCardSpacing
                    clip: true
                    model: history
                    delegate: NotifCard {
                        width: ListView.view ? ListView.view.width : 0
                        summary: model.summary
                        body: model.body
                        appName: model.app
                        image: model.image
                        urgency: model.urgency
                        timeText: model.time
                        onDismissed: history.remove(index)
                    }
                }
            }
        }
    }

    // =======================================================================
    // Reusable components
    // =======================================================================

    component NotifCard: Rectangle {
        id: card
        property string summary
        property string body
        property string appName
        property string image
        property int urgency
        property string timeText
        signal dismissed()

        radius: Style.notifCardRadius
        antialiasing: true
        clip: true
        border.width: 1
        border.color: urgency === 2 ? Style.criticalBorder : Theme.glassEdge

        // height drives off content; content width drives off card width
        implicitHeight: row.implicitHeight + Style.notifCardVPadding

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.cardGradientTopAlpha) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Style.cardGradientBotAlpha) }
        }

        // top sheen
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 1
            height: parent.height * Style.cardSheenRatio
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaTop) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaBottom) }
            }
        }

        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.notifCardPadding
            spacing: Style.notifCardSpacing

            // image / icon
            Rectangle {
                Layout.preferredWidth: Style.notifIconSize
                Layout.preferredHeight: Style.notifIconSize
                Layout.alignment: Qt.AlignTop
                radius: Style.notifIconRadius
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.accentTintIcon)
                border.width: 1
                border.color: Theme.glassEdge

                Image {
                    anchors.fill: parent
                    anchors.margins: Style.notifIconImagePad
                    source: card.image
                    fillMode: Image.PreserveAspectCrop
                    visible: card.image.length > 0
                    smooth: true
                }
                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Theme.accent
                    font.pixelSize: Style.notifIconFallbackSize
                    visible: card.image.length === 0
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.pillRowSpacing
                    Text {
                        text: card.summary
                        color: Theme.textPrimary
                        font.pixelSize: Style.notifSummarySize
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        text: card.timeText
                        color: Theme.textMuted
                        font.pixelSize: Style.notifTimeSize
                    }
                    // close button
                    Rectangle {
                        Layout.preferredWidth: Style.notifCloseSize
                        Layout.preferredHeight: Style.notifCloseSize
                        radius: Style.notifCloseRadius
                        color: closeHover.containsMouse
                            ? Style.closeHoverBg
                            : Qt.rgba(1, 1, 1, Style.sheenAlphaTopStrong)
                        border.width: 1
                        border.color: Theme.glassEdge
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: closeHover.containsMouse ? "white" : Theme.textPrimary
                            font.pixelSize: Style.notifCloseFontSize
                            font.weight: Font.Bold
                        }
                        MouseArea {
                            id: closeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.dismissed()
                        }
                    }
                }
                Text {
                    text: card.body
                    color: Theme.textPrimary
                    font.pixelSize: Style.notifBodySize
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: Style.notifBodyMaxLines
                    Layout.fillWidth: true
                    visible: text.length > 0
                }
                Text {
                    text: card.appName
                    color: Theme.textMuted
                    font.pixelSize: Style.notifAppSize
                    Layout.fillWidth: true
                }
            }
        }
    }

    component QuickAction: Rectangle {
        id: qa
        property string label
        property string tooltip
        property var action: []
        property bool danger: false

        Layout.fillWidth: true
        implicitHeight: Style.quickActionHeight
        radius: Style.quickActionRadius
        antialiasing: true
        border.width: 1
        border.color: Theme.glassEdge

        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, hover.containsMouse ? Style.surfaceAlphaHover : 0.65) }
            GradientStop { position: 1.0; color: hover.containsMouse
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.accentQuickActionHover)
                : Qt.rgba(1, 1, 1, Style.surfaceAlphaPressed) }
        }
        Behavior on color { ColorAnimation { duration: Style.hoverAnimMs } }

        // sheen
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 1
            height: parent.height * Style.quickActionSheenRatio
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaTop) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, Style.sheenAlphaBottomZero) }
            }
        }

        Text {
            anchors.centerIn: parent
            text: qa.label
            color: qa.danger ? Style.powerDangerText : Theme.textPrimary
            font.pixelSize: Style.quickActionIconSize
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (qa.action.length > 0) Quickshell.execDetached(qa.action)
                notifs.centerOpen = false
            }
        }
    }

    component GlossyButton: Rectangle {
        property string text: ""
        signal clicked()
        implicitWidth: lbl.implicitWidth + (Style.pillPaddingX + 4)
        implicitHeight: Style.pillHeight
        radius: Style.pillRadius
        color: hover.containsMouse
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.accentTintHover)
            : Qt.rgba(1, 1, 1, Style.sheenAlphaTopStrong)
        border.width: 1
        border.color: Theme.glassEdge
        Behavior on color { ColorAnimation { duration: Style.hoverAnimMs } }

        Text {
            id: lbl
            anchors.centerIn: parent
            text: parent.text
            color: Theme.textPrimary
            font.pixelSize: Style.pillTextSize
            font.weight: Font.Medium
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component Toggle: Rectangle {
        id: tg
        property bool checked: false
        signal toggled()

        implicitWidth: Style.toggleWidth
        implicitHeight: Style.toggleHeight
        radius: Style.toggleRadius
        color: checked
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.accentToggleAlpha)
            : Qt.rgba(1, 1, 1, Style.sheenAlphaTopStrong)
        border.width: 1
        border.color: Theme.glassEdge
        Behavior on color { ColorAnimation { duration: Style.toggleAnimMs } }

        Rectangle {
            width: Style.toggleKnobSize
            height: Style.toggleKnobSize
            radius: Style.toggleKnobSize / 2
            x: tg.checked ? tg.width - width - Style.toggleKnobInset : Style.toggleKnobInset
            anchors.verticalCenter: parent.verticalCenter
            color: Style.toggleKnobColor
            border.color: Theme.glassEdge
            border.width: 1
            Behavior on x { NumberAnimation { duration: Style.toggleAnimMs; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tg.toggled()
        }
    }
}
