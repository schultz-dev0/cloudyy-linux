// NotifPanel.qml
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "modules/controlcenter"
import "modules/controlcenter/tiles"

PanelWindow {
    id: panel

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int panelWidth:   380
    readonly property int panelHeight:  900
    readonly property int topGap:        10
    readonly property int rightGap:      20
    readonly property int panelRadius:   24
    readonly property int sectionRadius: 16

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool open:             false
    property bool dnd:              false
    property var  notifServer:      null
    property var  sliderController: null
    signal close()
    signal dndToggle()
    onOpenChanged: {
        if (open && sliderController) sliderController.refreshAll()
        if (open) { wifiTile.refresh(); btTile.refresh(); darkTile.refresh() }
    }

    // ── Clock ─────────────────────────────────────────────────────────────────
    property string clockText: ""
    Timer {
        interval: 60000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: panel.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm")
    }

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
    color:          "transparent"
    visible:        open

    // ── Panel shell ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill:  parent
        radius:        panel.panelRadius
        color:  Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                              Theme.outline_variant.b, 0.3)
        border.width: 1

        ColumnLayout {
            anchors { fill: parent; margins: 18 }
            spacing: 12

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text:           "Control Center"
                    color:          Theme.on_surface
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight:    Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text:           panel.clockText
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            // ── Tile grid ─────────────────────────────────────────────────────
            TileGrid {
                Layout.fillWidth: true

                WifiTile { id: wifiTile }

                DndTile {
                    id:        dndTile
                    dnd:       panel.dnd
                    onDndToggle: panel.dndToggle()
                }

                BluetoothTile { id: btTile }

                DarkModeTile { id: darkTile }

                NightLightTile {
                    id:               nlTile
                    sliderController: panel.sliderController
                }
            }

            // ── Display ───────────────────────────────────────────────────────
            Rectangle {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                radius:  panel.sectionRadius
                color:   Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                      Theme.outline_variant.b, 0.25)
                border.width:   1
                implicitHeight: 72

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text:           "Display"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight:    Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius:         10
                        color:  Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                                        Theme.surface_container.b, 0.5)
                        implicitHeight: 38

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10

                            Slider {
                                id:              brightnessSlider
                                Layout.fillWidth: true
                                from:    1; to: 100; live: true
                                value:   panel.sliderController
                                    ? panel.sliderController.brightnessValue : 50
                                palette.highlight: Theme.tertiary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setBrightness(value)

                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding
                                       + brightnessSlider.availableHeight / 2 - height / 2
                                    width: brightnessSlider.availableWidth; height: 10; radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r,
                                                   Theme.surface_container_high.g,
                                                   Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: brightnessSlider.palette.highlight
                                        opacity: brightnessSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: brightnessSlider.leftPadding
                                       + brightnessSlider.visualPosition
                                       * (brightnessSlider.availableWidth - width)
                                    y: brightnessSlider.topPadding
                                       + brightnessSlider.availableHeight / 2 - height / 2
                                    width: 16; height: 16; radius: 8
                                    color: brightnessSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g,
                                                          Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: brightnessSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 30; height: 30; radius: 10
                                color: Qt.rgba(Theme.surface_container_high.r,
                                               Theme.surface_container_high.g,
                                               Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r,
                                                      Theme.outline_variant.g,
                                                      Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent; text: "󰃠"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (panel.sliderController)
                                        panel.sliderController.showBrightness()
                                }
                            }
                        }
                    }
                }
            }

            // ── Sound ─────────────────────────────────────────────────────────
            Rectangle {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                radius:  panel.sectionRadius
                color:   Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.3)
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                      Theme.outline_variant.b, 0.25)
                border.width:   1
                implicitHeight: 72

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    Text {
                        text:           "Sound"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight:    Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius:         10
                        color:  Qt.rgba(Theme.surface_container.r, Theme.surface_container.g,
                                        Theme.surface_container.b, 0.5)
                        implicitHeight: 38

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            spacing: 10

                            Slider {
                                id:              volumeSlider
                                Layout.fillWidth: true
                                from: 0; to: 100; live: true
                                value: panel.sliderController
                                    ? panel.sliderController.volumeValue : 50
                                palette.highlight: Theme.primary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setVolume(value)

                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    width: volumeSlider.availableWidth; height: 10; radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r,
                                                   Theme.surface_container_high.g,
                                                   Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: volumeSlider.visualPosition * parent.width
                                        height: parent.height; radius: parent.radius
                                        color: volumeSlider.palette.highlight
                                        opacity: volumeSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: volumeSlider.leftPadding
                                       + volumeSlider.visualPosition
                                       * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    width: 16; height: 16; radius: 8
                                    color: volumeSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g,
                                                          Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: volumeSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 30; height: 30; radius: 10
                                color: Qt.rgba(Theme.surface_container_high.r,
                                               Theme.surface_container_high.g,
                                               Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r,
                                                      Theme.outline_variant.g,
                                                      Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text:  panel.sliderController
                                        ? panel.sliderController.volumeIcon : "󰕾"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (panel.sliderController)
                                        panel.sliderController.toggleMute()
                                }
                            }
                        }
                    }
                }
            }

            // ── Media card ────────────────────────────────────────────────────
            MediaCard { Layout.fillWidth: true }

            // ── Notification list ─────────────────────────────────────────────
            ListView {
                id: notifList
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: 6
                clip:    true
                model:   panel.notifServer ? panel.notifServer.trackedNotifications : null

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width:  ListView.view.width
                    height: cardContent.implicitHeight + 28
                    radius: 18
                    color: card.modelData.urgency === 2
                        ? Qt.rgba(Theme.error_container.r, Theme.error_container.g,
                                  Theme.error_container.b, 0.2)
                        : Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
                    border.color: card.modelData.urgency === 2
                        ? Theme.error
                        : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g,
                                  Theme.outline_variant.b, 0.4)
                    border.width: 1

                    Column {
                        id: cardContent
                        anchors { left: parent.left; right: parent.right
                                  top: parent.top; margins: 14 }
                        spacing: 4

                        Text {
                            text:           card.modelData.appName
                            color:          Theme.on_surface_variant
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            width:          parent.width
                            text:           card.modelData.summary
                            color:          Theme.on_surface
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            font.weight:    Font.Bold
                            wrapMode:       Text.WordWrap
                        }
                        Text {
                            visible:  card.modelData.body !== ""
                            width:    parent.width
                            text:     card.modelData.body
                            color:    Qt.rgba(Theme.on_surface.r, Theme.on_surface.g,
                                             Theme.on_surface.b, 0.8)
                            font.family:      "JetBrainsMono Nerd Font"
                            font.pixelSize:   13
                            wrapMode:         Text.WordWrap
                            maximumLineCount: 3
                            elide:            Text.ElideRight
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: card.modelData.dismiss() }
                }

                Text {
                    anchors.centerIn: parent
                    visible:        notifList.count === 0
                    text:           "No notifications"
                    color:  Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g,
                                    Theme.on_surface_variant.b, 0.4)
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                }
            }
        }
    }
}
