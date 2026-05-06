pragma ComponentBehavior: Bound

// NotifPanel.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "modules/controlcenter"
import "modules/controlcenter/tiles"
import "modules/calendar"

PanelWindow {
    id: panel

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int panelWidth: 380
    readonly property int panelMaxHeight: 900
    readonly property int topGap: 10
    readonly property int rightGap: 20
    readonly property int panelRadius: 24
    readonly property int sectionRadius: 16
    readonly property int panelPadding: 18
    readonly property int emptyNotifHeight: 36
    readonly property int notifCardShadowSideInset: 18
    readonly property int notifCardShadowTopInset: 10
    readonly property int notifCardShadowBottomInset: 22
    readonly property bool hasNotifications: (panel.notifServer?.trackedNotifications?.count ?? 0) > 0

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool open: false
    property bool dnd: false
    property bool calculatorOpen: false
    property var notifServer: null
    property var sliderController: null
    signal close
    signal dndToggle
    signal calculatorToggle
    onOpenChanged: {
        if (open && sliderController)
            sliderController.refreshAll();
        if (open) {
            wifibtTile.refresh();
            darkTile.refresh();
        }
    }

    // ── Clock ─────────────────────────────────────────────────────────────────
    property string clockText: ""
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: panel.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm")
    }

    // ── One-shot launcher ─────────────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        procProto.createObject(panel, {
            command: cmd
        }).running = true;
    }

    // ── Window setup ──────────────────────────────────────────────────────────
    anchors {
        top: true
        right: true
    }
    margins {
        top: topGap
        right: rightGap
    }
    implicitWidth: panelWidth
    implicitHeight: Math.min(panelMaxHeight, contentColumn.implicitHeight + panelPadding * 2)
    color: "transparent"
    visible: open

    // ── Panel shell ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: panel.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        ColumnLayout {
            id: contentColumn
            anchors {
                fill: parent
                margins: panel.panelPadding
            }
            spacing: 12

            // ── Header ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Control Center"
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text: panel.clockText
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            // ── Tile grid ─────────────────────────────────────────────────────
            //
            // Layout (macOS-style, two RowLayout sections):
            //
            //   Row 1: [ WiFi + Bluetooth (tall) ]  [ Do Not Disturb ]
            //          [                         ]  [ Dark Mode      ]
            //   Row 2: [ Night Light             ]  [ Calculator     ]
            //
            // Using explicit RowLayout / ColumnLayout instead of GridLayout
            // rowSpan so ElevatedEffect shadows never fight z-ordering between
            // sibling tiles — each tile lives in its own layout branch.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                // ── First section: tall combined tile beside two stacked tiles ──
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    WifiBluetoothTile {
                        id: wifibtTile
                    }

                    ColumnLayout {
                        spacing: 6

                        DndTile {
                            id: dndTile
                            Layout.fillWidth: true
                            dnd: panel.dnd
                            onDndToggle: panel.dndToggle()
                        }

                        DarkModeTile {
                            id: darkTile
                            Layout.fillWidth: true
                        }
                    }
                }

                // ── Second section: two tiles side by side ─────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    NightLightTile {
                        id: nlTile
                        Layout.fillWidth: true
                        sliderController: panel.sliderController
                    }

                    CalculatorTile {
                        id: calcTile
                        Layout.fillWidth: true
                        open: panel.calculatorOpen
                        onClicked: panel.calculatorToggle()
                    }
                }
            }

            // ── Display ───────────────────────────────────────────────────────
            Rectangle {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                radius: panel.sectionRadius
                color: Theme.surface_container
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
                border.width: 1
                implicitHeight: 72

                ElevatedEffect {
                    target: parent
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    Text {
                        text: "Display"
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.5)
                        implicitHeight: 27

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 10

                            Slider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                from: 1
                                to: 100
                                live: true
                                value: panel.sliderController ? panel.sliderController.brightnessValue : 50
                                palette.highlight: Theme.tertiary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setBrightness(value)

                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    width: brightnessSlider.availableWidth
                                    height: 10
                                    radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: parent.radius
                                        color: brightnessSlider.palette.highlight
                                        opacity: brightnessSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: brightnessSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: brightnessSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 25
                                height: 25
                                radius: 16
                                color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰃠"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 16
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
                radius: panel.sectionRadius
                color: Theme.surface_container
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
                border.width: 1
                implicitHeight: 72

                ElevatedEffect {
                    target: parent
                }

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 8

                    Text {
                        text: "Sound"
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 16
                        color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.5)
                        implicitHeight: 25

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 12
                            }
                            spacing: 10

                            Slider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                live: true
                                value: panel.sliderController ? panel.sliderController.volumeValue : 50
                                palette.highlight: Theme.primary
                                onMoved: if (panel.sliderController)
                                    panel.sliderController.setVolume(value)

                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: volumeSlider.availableWidth
                                    height: 10
                                    radius: 999
                                    color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.45)
                                    Rectangle {
                                        width: volumeSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: parent.radius
                                        color: volumeSlider.palette.highlight
                                        opacity: volumeSlider.enabled ? 1 : 0.35
                                    }
                                }
                                handle: Rectangle {
                                    x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: volumeSlider.pressed ? Theme.primary : Theme.on_surface
                                    border.color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.8)
                                    border.width: 1
                                    opacity: volumeSlider.enabled ? 1 : 0.4
                                }
                            }

                            Rectangle {
                                width: 25
                                height: 25
                                radius: 16
                                color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.55)
                                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: panel.sliderController ? panel.sliderController.volumeIcon : "󰕾"
                                    color: Theme.on_surface
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 16
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

            // ── Calendar mini strip ───────────────────────────────────────────
            CalendarMiniSection {
                Layout.fillWidth: true
            }

            // ── Media card ────────────────────────────────────────────────────
            MediaCard {
                Layout.fillWidth: true
            }

            // ── Notification stack ────────────────────────────────────────────
            //
            // Cards are layered using absolute positioning + z-order.
            // Card 0 (front): full width, full opacity.
            // Card 1 (behind): slightly narrower, lower opacity, peeking below.
            // Card 2 (behind): same pattern — max 3 cards shown.
            //
            // The container's implicitHeight tracks the front card live so the
            // panel expands/contracts smoothly as notification content changes.
            Item {
                id: notifStack
                Layout.fillWidth: true

                // ── Tunables ──────────────────────────────────────────────────
                readonly property int maxVisible: 3
                readonly property int peekHeight: 12  // px each card peeks below the one in front
                readonly property int widthInset:  8  // px inset on each side per depth level

                // Front-card height kept in sync via delegate bindings below.
                property real frontCardHeight: panel.notifCardShadowTopInset
                                             + 72
                                             + panel.notifCardShadowBottomInset

                readonly property int notifCount: notifRepeater.count
                readonly property int shownCount: Math.min(notifCount, maxVisible)

                implicitHeight: notifCount === 0
                    ? panel.emptyNotifHeight
                    : frontCardHeight + Math.max(0, shownCount - 1) * peekHeight

                Behavior on implicitHeight {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Repeater {
                    id: notifRepeater
                    model: panel.notifServer ? panel.notifServer.trackedNotifications : null

                    delegate: Item {
                        id: cardWrapper

                        required property var modelData
                        required property int index

                        visible: index < notifStack.maxVisible

                        // Higher index = further back = lower z = rendered first.
                        z:       notifStack.maxVisible - index

                        // Each card shifts inward and downward to create depth.
                        x:       index * notifStack.widthInset
                        y:       index * notifStack.peekHeight
                        width:   notifStack.width - (index * notifStack.widthInset * 2)
                        height:  panel.notifCardShadowTopInset + card.height + panel.notifCardShadowBottomInset
                        opacity: 1.0 - (index * 0.18)

                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        // Keep the stack container's implicitHeight in sync with
                        // the actual front-card height (content may wrap/grow).
                        onHeightChanged:       if (index === 0) notifStack.frontCardHeight = height
                        Component.onCompleted: if (index === 0) notifStack.frontCardHeight = height

                        ElevatedEffect { target: card }

                        Rectangle {
                            id: card
                            x:      panel.notifCardShadowSideInset
                            y:      panel.notifCardShadowTopInset
                            width:  parent.width - panel.notifCardShadowSideInset * 2
                            height: cardContent.implicitHeight + 28
                            radius: 18
                            color: cardWrapper.modelData.urgency === 2
                                ? Qt.tint(Theme.surface_container, Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12))
                                : Theme.surface_container
                            border.color: cardWrapper.modelData.urgency === 2
                                ? Theme.error
                                : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                            border.width: 1

                            Column {
                                id: cardContent
                                anchors {
                                    left:    parent.left
                                    right:   parent.right
                                    top:     parent.top
                                    margins: 14
                                }
                                spacing: 4

                                Text {
                                    text:           cardWrapper.modelData.appName
                                    color:          Theme.on_surface_variant
                                    font.family:    "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }

                                Text {
                                    width:          parent.width
                                    text:           cardWrapper.modelData.summary
                                    color:          Theme.on_surface
                                    font.family:    "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                    font.weight:    Font.Bold
                                    wrapMode:       Text.WordWrap
                                }

                                Text {
                                    visible:          cardWrapper.modelData.body !== ""
                                    width:            parent.width
                                    text:             cardWrapper.modelData.body
                                    color:            Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.8)
                                    font.family:      "JetBrainsMono Nerd Font"
                                    font.pixelSize:   13
                                    wrapMode:         Text.WordWrap
                                    maximumLineCount: 3
                                    elide:            Text.ElideRight
                                }
                            }

                            // Only the front card is interactive — dismissing it
                            // reveals the next card in the stack.
                            MouseArea {
                                anchors.fill: parent
                                enabled:      cardWrapper.index === 0
                                onClicked:    cardWrapper.modelData.dismiss()
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible:          notifStack.notifCount === 0
                    text:             "No notifications"
                    color:            Qt.rgba(Theme.on_surface_variant.r, Theme.on_surface_variant.g, Theme.on_surface_variant.b, 0.4)
                    font.family:      "JetBrainsMono Nerd Font"
                    font.pixelSize:   13
                }
            }
        }
    }
}
