pragma ComponentBehavior: Bound

// NotifPanel.qml — lists NotificationServer.trackedNotifications (see NotifPanelService.track in shell.qml).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "modules/controlcenter"
import "modules/controlcenter/tiles"
import "modules/calendar"
import "modules/notifpanel" as QuickNotifPanel

PanelWindow {
    id: panel

    // ── Tunables ─────────────────────────────────────────────────────────────
    readonly property int panelWidth: 380
    readonly property int panelMaxHeight: 900
    readonly property int topGap: 10
    readonly property int rightGap: 20
    readonly property int panelRadius: 0
    readonly property int sectionRadius: 0
    readonly property int panelPadding: 18
    readonly property int emptyNotifHeight: 36
    readonly property int notifCardShadowSideInset: 18
    readonly property int notifCardShadowTopInset: 10
    readonly property int notifCardShadowBottomInset: 22
    readonly property int notifPanelMaxVisible: 3
    property var visibleNotifications: []

    readonly property int trackedCount: {
        const vals = panel.notifServer?.trackedNotifications?.values;
        return vals ? vals.length : 0;
    }
    readonly property bool hasNotifications: panel.trackedCount > 0

    function refreshVisibleNotifications() {
        const vals = panel.notifServer?.trackedNotifications?.values;
        if (!vals || vals.length === 0) {
            panel.visibleNotifications = [];
            return;
        }
        const n = panel.notifPanelMaxVisible;
        // Newest last in model — show most recent at the front of the stack.
        panel.visibleNotifications = vals.length <= n
            ? vals.slice().reverse()
            : vals.slice(vals.length - n).reverse();
    }

    Connections {
        target: panel.notifServer
        function onTrackedNotificationsChanged() {
            panel.refreshVisibleNotifications();
        }
    }

    Connections {
        target: panel.notifServer?.trackedNotifications
        enabled: panel.notifServer !== null
        function onValuesChanged() {
            panel.refreshVisibleNotifications();
        }
    }

    Component.onCompleted: panel.refreshVisibleNotifications()

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool open: false
    property bool dnd: false
    property var notifServer: null
    property var sliderController: null
    property bool suppressLayoutAnim: false
    signal close
    signal dndToggle

    readonly property int openFadeMs: Perf.msHalf(80)

    function snapNotificationsEmpty() {
        suppressLayoutAnim = true;
        visibleNotifications = [];
    }

    function endNotificationSnap() {
        suppressLayoutAnim = false;
        refreshVisibleNotifications();
    }
    onOpenChanged: {
        if (!open)
            return;

        QuickNotifPanel.NotifPanelService.markAllRead();
        panel.refreshVisibleNotifications();
        panel.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm");

        // Defer tile/slider refresh so open animation isn't blocked on subprocess I/O.
        Qt.callLater(() => {
            if (!panel.open)
                return;
            if (panel.sliderController)
                panel.sliderController.refreshAll();
            wifibtTile.refresh();
            darkTile.refresh();
        });
    }

    // ── Clock ─────────────────────────────────────────────────────────────────
    property string clockText: ""
    Timer {
        interval: 60000
        repeat: true
        running: panel.open
        triggeredOnStart: true
        onTriggered: panel.clockText = Qt.formatDateTime(new Date(), "ddd dd MMM · hh:mm")
    }

    // ── One-shot launcher ─────────────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        const p = procProto.createObject(panel, {
            command: cmd
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
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

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:control"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0

    // ── Panel shell ───────────────────────────────────────────────────────────
    // Resin material — real theme-hue tint, not neutral glass. See
    // Theme.qml's resin() comment for the keycap reasoning.
    Rectangle {
        id: panelShell
        anchors.fill: parent
        radius: panel.panelRadius
        color: Theme.resin(Theme.resinFillAlpha)
        border.width: 1
        border.color: Theme.resinBorder
        clip: true

        opacity: panel.open ? 1 : 0
        transformOrigin: Item.TopRight
        Behavior on opacity {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: panel.openFadeMs; easing.type: Easing.OutQuad }
        }

        // Gloss — light catching the material's upper edge.
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * 0.4
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.resinGloss }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Inner glow — a hint of structure beneath the material, like the
        // switch under a keycap, not the desktop behind it. Actually blurred
        // (not just low-opacity) so it reads as soft light, not a defined
        // shape sitting on top of the fill. Corner-anchored with the center
        // pushed past the edge (clipped by panelShell) instead of a
        // percentage-of-height position, so it never lands under a text row
        // regardless of how much content the panel holds.
        Rectangle {
            width: parent.width * 0.4
            height: width
            radius: width / 2
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: -width * 0.5
                bottomMargin: -height * 0.5
            }
            color: Theme.resinGlow
            opacity: 0.5
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 80 }
        }

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
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text: panel.clockText
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            // ── Tile grid ─────────────────────────────────────────────────────
            //
            // Layout (macOS-style, two RowLayout sections):
            //
            //   Row 1: [ WiFi + Bluetooth (tall) ]  [ Do Not Disturb ]
            //   Row 2: [ Night Light             ]
            //
            // Using explicit RowLayout / ColumnLayout instead of GridLayout rowSpan.
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

                    }
                }

                // ── Second section: night light ────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    NightLightTile {
                        id: nlTile
                        Layout.fillWidth: true
                        sliderController: panel.sliderController
                    }
                }

                // ── Third section: system overview tile ───────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    SystemTile {
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

            // ── Display ───────────────────────────────────────────────────────
            Item {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                implicitHeight: displayCol.implicitHeight

                ColumnLayout {
                    id: displayCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 6

                    Text {
                        text: "Display"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Slider {
                            id: brightnessSlider
                            Layout.fillWidth: true
                            from: 1
                            to: 100
                            live: true
                            value: panel.sliderController ? panel.sliderController.brightnessValue : 50
                            onMoved: if (panel.sliderController)
                                panel.sliderController.setBrightness(value)

                            // Tick-gauge track — filled ticks (accent) up to
                            // the current value, unfilled ticks (hairline)
                            // past it. Reads as a level meter, not a pill.
                            background: Item {
                                id: brightnessTrack
                                x: brightnessSlider.leftPadding
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                width: brightnessSlider.availableWidth
                                height: 10
                                readonly property int tickCount: 22
                                readonly property real tickGap: width / (tickCount - 1)

                                Repeater {
                                    model: brightnessTrack.tickCount
                                    delegate: Rectangle {
                                        required property int index
                                        x: index * brightnessTrack.tickGap - width / 2
                                        width: 1.5
                                        height: brightnessTrack.height
                                        color: (index / (brightnessTrack.tickCount - 1)) <= brightnessSlider.visualPosition
                                            ? Theme.accent
                                            : Theme.hairline
                                    }
                                }
                            }
                            handle: Rectangle {
                                x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                width: 2
                                height: 16
                                radius: 0
                                color: Theme.text
                                opacity: brightnessSlider.enabled ? 1 : 0.4
                            }
                        }

                        Text {
                            text: (panel.sliderController ? Math.round(panel.sliderController.brightnessValue) : 50) + "%"
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 0
                            color: "transparent"
                            border.color: Theme.hairline
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "󰃠"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
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

            // ── Sound ─────────────────────────────────────────────────────────
            Item {
                visible: !!panel.sliderController
                Layout.fillWidth: true
                implicitHeight: soundCol.implicitHeight

                ColumnLayout {
                    id: soundCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 6

                    Text {
                        text: "Sound"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.6
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Slider {
                            id: volumeSlider
                            Layout.fillWidth: true
                            from: 0
                            to: 100
                            live: true
                            value: panel.sliderController ? panel.sliderController.volumeValue : 50
                            onMoved: if (panel.sliderController)
                                panel.sliderController.setVolume(value)

                            background: Item {
                                id: volumeTrack
                                x: volumeSlider.leftPadding
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                width: volumeSlider.availableWidth
                                height: 10
                                readonly property int tickCount: 22
                                readonly property real tickGap: width / (tickCount - 1)

                                Repeater {
                                    model: volumeTrack.tickCount
                                    delegate: Rectangle {
                                        required property int index
                                        x: index * volumeTrack.tickGap - width / 2
                                        width: 1.5
                                        height: volumeTrack.height
                                        color: (index / (volumeTrack.tickCount - 1)) <= volumeSlider.visualPosition
                                            ? Theme.accent
                                            : Theme.hairline
                                    }
                                }
                            }
                            handle: Rectangle {
                                x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                width: 2
                                height: 16
                                radius: 0
                                color: Theme.text
                                opacity: volumeSlider.enabled ? 1 : 0.4
                            }
                        }

                        Text {
                            text: (panel.sliderController ? Math.round(panel.sliderController.volumeValue) : 50) + "%"
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 0
                            color: "transparent"
                            border.color: Theme.hairline
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: panel.sliderController ? panel.sliderController.volumeIcon : "󰕾"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
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

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

            // ── Calendar mini strip ───────────────────────────────────────────
            CalendarMiniSection {
                Layout.fillWidth: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

            // ── Media card ────────────────────────────────────────────────────
            MediaCard {
                Layout.fillWidth: true
                active: panel.open
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
                readonly property int maxVisible: panel.notifPanelMaxVisible
                readonly property int peekHeight: 12  // px each card peeks below the one in front
                readonly property int widthInset:  8  // px inset on each side per depth level
                readonly property int stackUnitHeight: panel.notifCardShadowTopInset
                                                     + 96
                                                     + panel.notifCardShadowBottomInset

                readonly property int notifCount: panel.trackedCount
                readonly property int displayCount: notifStack.suppressLayoutAnim
                    ? panel.visibleNotifications.length
                    : notifCount
                readonly property int shownCount: Math.min(displayCount, maxVisible)
                readonly property bool suppressLayoutAnim: panel.suppressLayoutAnim

                implicitHeight: displayCount === 0
                    ? panel.emptyNotifHeight
                    : stackUnitHeight + Math.max(0, shownCount - 1) * peekHeight

                Repeater {
                    id: notifRepeater
                    model: panel.visibleNotifications

                    delegate: Item {
                        id: cardWrapper

                        required property var modelData
                        required property int index

                        visible: panel.open && index < notifStack.maxVisible

                        // Higher index = further back = lower z = rendered first.
                        z:       notifStack.maxVisible - index

                        // Each card shifts inward and downward to create depth.
                        x:       index * notifStack.widthInset
                        y:       index * notifStack.peekHeight
                        width:   notifStack.width - (index * notifStack.widthInset * 2)
                        height:  panel.notifCardShadowTopInset + card.height + panel.notifCardShadowBottomInset
                        opacity: 1.0 - (index * 0.18)

                        Rectangle {
                            id: card
                            x:      panel.notifCardShadowSideInset
                            y:      panel.notifCardShadowTopInset
                            width:  parent.width - panel.notifCardShadowSideInset * 2
                            height: cardContent.implicitHeight + 28
                            radius: 4
                            color: cardWrapper.modelData.urgency === 2
                                ? Qt.tint(Qt.rgba(Theme.surfaceRaised.r, Theme.surfaceRaised.g, Theme.surfaceRaised.b, 0.95), Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.12))
                                : Qt.rgba(Theme.surfaceRaised.r, Theme.surfaceRaised.g, Theme.surfaceRaised.b, 0.95)
                            border.color: cardWrapper.modelData.urgency === 2
                                ? Theme.error
                                : Theme.hairline
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
                                    color:          Theme.textMuted
                                    font.family:    "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }

                                Text {
                                    width:          parent.width
                                    text:           cardWrapper.modelData.summary
                                    color:          Theme.text
                                    font.family:    "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                    font.weight:    Font.Bold
                                    wrapMode:       Text.WordWrap
                                }

                                Text {
                                    visible:          cardWrapper.modelData.body !== ""
                                    width:            parent.width
                                    text:             cardWrapper.modelData.body
                                    color:            Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.8)
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
                    visible:          notifStack.displayCount === 0
                    text:             "No notifications"
                    color:            Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.4)
                    font.family:      "JetBrainsMono Nerd Font"
                    font.pixelSize:   13
                }
            }
        }
    }
}
