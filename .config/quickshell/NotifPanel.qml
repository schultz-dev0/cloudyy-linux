pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

PanelWindow {
    id: panel

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int panelWidth:     380
    readonly property int panelHeight:    800
    readonly property int topGap:          10
    readonly property int rightGap:        20
    readonly property int panelRadius:     24
    readonly property int sectionRadius:   16

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool open:        false
    property bool dnd:         false
    property var  notifServer: null
    signal close()
    signal dndToggle()

    // ── One-shot launcher ─────────────────────────────────────────────────────
    Component { id: procProto; Process {} }
    function launch(cmd) {
        procProto.createObject(panel, { command: cmd }).running = true
    }

    // ── Window setup ──────────────────────────────────────────────────────────
    anchors { top: true; right: true }
    margins { top: topGap; right: rightGap }
    implicitWidth:  panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    visible: open

    // ── Panel ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: panel.panelRadius
        color:  Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 12

            // ── Title ─────────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Notifications"
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 64; height: 30; radius: 10
                    color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.4)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text:        "Clear"
                        color:       Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!panel.notifServer) return
                            const list = panel.notifServer.trackedNotifications.values
                            for (const n of list) n.dismiss()
                        }
                    }
                }
            }

            // ── Quick toggles ─────────────────────────────────────────────────
            component Toggle: Rectangle {
                id: tog
                property string icon: ""
                property bool   active: false
                signal clicked()

                width: 64; height: 56; radius: panel.sectionRadius
                color: active ? Theme.primary
                    : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.45)
                border.color: active ? Theme.primary
                    : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text:        tog.icon
                    color:       tog.active ? Theme.on_primary : Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 20
                }
                MouseArea { anchors.fill: parent; onClicked: tog.clicked() }
            }

            Row {
                Layout.fillWidth: true
                spacing: 8
                Toggle { icon: "󰖩"; onClicked: panel.launch(["uwsm-app", "--", "nm-connection-editor"]) }
                Toggle { icon: "󰂯";  onClicked: panel.launch(["uwsm-app", "--", "cloud-center bluetooth"]) }
                Toggle { icon: "󱐋"; onClicked: panel.launch(["bash", "-c", "uwsm-app -- python3 ~/cloudyy_scripts/sliders/cloudyy_sliders.py"]) }
                Toggle { icon: "󰸉"; onClicked: panel.launch(["bash", "-c", "~/cloudyy_scripts/rofi/appearance.sh --select"]) }
                Toggle { icon: "󱩌"; onClicked: panel.launch(["bash", "-c", "~/cloudyy_scripts/theme_controller.sh toggle"]) }
            }

            // ── DND ───────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 48
                radius: panel.sectionRadius
                color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    Text {
                        text: "󰂛  Do Not Disturb"
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 44; height: 24; radius: 12
                        color: panel.dnd ? Theme.primary
                            : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            id: dndKnob
                            width: 18; height: 18; radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: panel.dnd ? parent.width - width - 3 : 3
                            color: panel.dnd ? Theme.on_primary : Theme.on_surface_variant
                            Behavior on x     { NumberAnimation  { duration: 150; easing.type: Easing.InOutQuad } }
                            Behavior on color { ColorAnimation   { duration: 150 } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: panel.dndToggle() }
                    }
                }
            }

            // ── Notification list ─────────────────────────────────────────────
            ListView {
                id: notifList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                clip:    true
                model:   panel.notifServer ? panel.notifServer.trackedNotifications : null

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width:  notifList.width
                    height: cardContent.implicitHeight + 28
                    radius: 18
                    color: card.modelData.urgency === 2
                        ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.2)
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                    border.color: card.modelData.urgency === 2
                        ? Theme.error
                        : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1

                    Column {
                        id: cardContent
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                        spacing: 4

                        Text {
                            text:        card.modelData.appName
                            color:       Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            width:       parent.width
                            text:        card.modelData.summary
                            color:       Theme.on_surface
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            wrapMode:    Text.WordWrap
                        }
                        Text {
                            visible:     card.modelData.body !== ""
                            width:       parent.width
                            text:        card.modelData.body
                            color:       Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.8)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            wrapMode:    Text.WordWrap
                            maximumLineCount: 3
                            elide:       Text.ElideRight
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: card.modelData.dismiss() }
                }

                Text {
                    anchors.centerIn: parent
                    visible: notifList.count === 0
                    text:  "No notifications"
                    color: Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g, Theme.on_surface_variant.b, 0.4)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                }
            }
        }
    }
}
