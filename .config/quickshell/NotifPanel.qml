pragma ComponentBehavior: Bound

// NotifPanel.qml — lists NotificationServer.trackedNotifications (see NotifPanelService.track in shell.qml).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "modules/controlcenter"
import "modules/controlcenter/tiles"
import "modules/calendar"
import "modules/notifpanel" as QuickNotifPanel
import "Readout.js" as Readout

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
    readonly property int notifChromeClearance: Theme.frameArmLength + Theme.frameInset
    readonly property int emptyNotifHeight: 36
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

    // ── First-open pre-warm (marginal — measure before trusting) ─────────────
    // `visible: open || _warmed` stops the scene graph being rebuilt on every
    // open, but the *first* open still pays ~370ms to build it (glyph raster
    // for ~40 Nerd-Font Text nodes + tiles + layout).
    //
    // ponytail: this blip flashes panelShell to 0.004 opacity (sub-perceptual,
    // still "painted") for 250ms at ~2.5s post-login, to force that build off
    // the first-open path. Mapping at opacity 0 isn't enough — Qt defers
    // node/glyph work until something paints. In practice it only pre-bakes
    // the static chrome, not the populated state (clock string, notif cards,
    // slider values all bind on real open), so measured first-open only
    // sometimes drops (~380 single → ~290+120 split) and sometimes doesn't.
    // It also adds a few 40-70ms startup hitches. If it's not earning its
    // keep on your setup, delete _warming + both Timers + the _warming branch
    // in panelShell.opacity; keep `property bool _warmed` and everything else.
    // Ceiling: a future Qt that culls near-zero-opacity subtrees silently
    // reverts this to the ~370ms first open (nothing breaks).
    property bool _warmed: false
    property bool _warming: false
    Timer {
        interval: 2500
        running: true
        repeat: false
        onTriggered: {
            if (panel._warmed)   // user already opened it — nothing to warm
                return;
            panel._warmed = true;
            panel._warming = true;
            warmBlipEnd.start();
        }
    }
    Timer {
        id: warmBlipEnd
        interval: 250
        onTriggered: panel._warming = false
    }

    onOpenChanged: {
        if (!open)
            return;

        panel._warmed = true;
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

    // Tick-gauge with a 16px grabber around the 2px bar. implicitHeight is
    // required — without it the control lays out at 0px and the ticks paint
    // as overflow you cannot drag.
    component GaugeSlider: Slider {
        id: control
        Layout.fillWidth: true
        Layout.preferredHeight: 22
        implicitHeight: 22
        live: true
        padding: 0
        readonly property int tickCount: 22
        background: Item {
            implicitWidth: 100
            implicitHeight: 22
            x: control.leftPadding
            y: control.topPadding
            width: control.availableWidth
            height: control.availableHeight
            readonly property real tickGap: width / Math.max(1, control.tickCount - 1)

            Repeater {
                model: control.tickCount
                delegate: Rectangle {
                    required property int index
                    x: index * control.background.tickGap - width / 2
                    y: (parent.height - height) / 2
                    width: 1.5
                    height: 10
                    color: (index / (control.tickCount - 1)) <= control.visualPosition
                        ? Theme.accent
                        : Theme.hairline
                }
            }
        }
        handle: Item {
            implicitWidth: 16
            implicitHeight: 22
            x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
            y: control.topPadding + control.availableHeight / 2 - height / 2
            Rectangle {
                anchors.centerIn: parent
                width: 2
                height: 16
                color: Theme.text
                opacity: control.enabled ? 1 : 0.4
            }
        }
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

    // Keep the layer surface mapped once warmed (see the pre-warm block up
    // top), instead of `visible: open`. Toggling visible tore down the
    // wl_surface + scene graph on every close and rebuilt it on the next
    // open — a ~300ms GUI-thread stall every time (measured). Now the build
    // happens once; opens after that just animate. Input is gated by `mask`
    // (compositor pass-through when closed) and panelShell.enabled; opacity
    // 0 hides it visually.
    visible: open || _warmed
    mask: Region { item: panel.open ? panelShell : null }

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:control"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0

    // ── Panel shell ───────────────────────────────────────────────────────────
    // Shared hero panel fill (Theme.resin* tokens). Neutral surface-toned
    // glass as of 2026-08-27 — was an accent-hue tint; see Theme.qml's
    // resin() comment.
    Rectangle {
        id: panelShell
        anchors.fill: parent
        radius: panel.panelRadius
        color: Theme.resin(Theme.resinFillAlpha)
        border.width: 0
        clip: true

        // 0.004 during the one-shot pre-warm blip: sub-perceptual but still
        // painted, which forces glyph/node build off the first-open path.
        opacity: panel.open ? 1 : (panel._warming ? 0.004 : 0)
        enabled: panel.open
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
        // switch under a keycap, not the desktop behind it. Corner-anchored
        // with the center pushed past the edge (clipped by panelShell) so it
        // never lands under a text row regardless of how much content the
        // panel holds.
        //
        // Three stacked translucent discs rather than one disc + MultiEffect
        // blur — the blur FBO was regenerated on the first render after each
        // map, landing on the same frames as the open animation. Plain
        // rounded rects cost nothing there. ponytail: 4th disc if banding shows.
        Item {
            width: parent.width * 0.4
            height: width
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: -width * 0.5
                bottomMargin: -height * 0.5
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width; height: width; radius: width / 2
                color: Theme.resinGlow; opacity: 0.12
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.68; height: width; radius: width / 2
                color: Theme.resinGlow; opacity: 0.16
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.4; height: width; radius: width / 2
                color: Theme.resinGlow; opacity: 0.22
            }
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
                Layout.topMargin: 6

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

                    DndTile {
                        id: dndTile
                        Layout.fillWidth: true
                        dnd: panel.dnd
                        onDndToggle: panel.dndToggle()
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

                        GaugeSlider {
                            id: brightnessSlider
                            from: 1
                            to: 100
                            value: panel.sliderController ? panel.sliderController.brightnessValue : 50
                            onMoved: if (panel.sliderController) {
                                panel.sliderController.setBrightness(value, false);
                                if (!pressed)
                                    panel.sliderController.scheduleBrightnessCommit();
                            }
                            onPressedChanged: if (!pressed && panel.sliderController)
                                panel.sliderController.commitBrightness()
                        }

                        Text {
                            text: Readout.osd("BRT", (panel.sliderController ? Math.round(panel.sliderController.brightnessValue) : 50) + "%")
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            Layout.preferredWidth: 78
                            horizontalAlignment: Text.AlignRight
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

            // ── Night Light temp only while the tile is on ─────────────────
            Item {
                visible: !!panel.sliderController && panel.sliderController.nightLightActive
                Layout.fillWidth: true
                implicitHeight: visible ? nlCol.implicitHeight : 0

                ColumnLayout {
                    id: nlCol
                    anchors { left: parent.left; right: parent.right }
                    spacing: 6

                    Text {
                        text: "Night Light"
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

                        GaugeSlider {
                            id: nightLightSlider
                            from: 1000
                            to: 6500
                            stepSize: 50
                            value: panel.sliderController ? panel.sliderController.nightLightTemp : 3500
                            onMoved: if (panel.sliderController) {
                                panel.sliderController.setNightLightTemp(value, false);
                                if (!pressed)
                                    panel.sliderController.scheduleNightLightCommit();
                            }
                            onPressedChanged: if (!pressed && panel.sliderController)
                                panel.sliderController.commitNightLightTemp()
                        }

                        Text {
                            text: Readout.osd("NL", (panel.sliderController ? panel.sliderController.nightLightTemp : 3500) + "K")
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            Layout.preferredWidth: 78
                            horizontalAlignment: Text.AlignRight
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
                                text: "󰖙"
                                color: Theme.text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.sliderController)
                                    panel.sliderController.showNightLight()
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

                        GaugeSlider {
                            id: volumeSlider
                            from: 0
                            to: 100
                            value: panel.sliderController ? panel.sliderController.volumeValue : 50
                            onMoved: if (panel.sliderController)
                                panel.sliderController.setVolume(value, false)
                        }

                        Text {
                            text: panel.sliderController && panel.sliderController.volumeMuted
                                ? Readout.osd("VOL", "MUTE")
                                : Readout.osd("VOL", (panel.sliderController ? Math.round(panel.sliderController.volumeValue) : 50) + "%")
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            Layout.preferredWidth: 78
                            horizontalAlignment: Text.AlignRight
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
                implicitWidth: contentColumn.width

                readonly property int maxVisible: panel.notifPanelMaxVisible
                readonly property int peekHeight: 12
                readonly property int widthInset: 8

                readonly property int notifCount: panel.trackedCount
                readonly property int displayCount: notifStack.suppressLayoutAnim
                    ? panel.visibleNotifications.length
                    : notifCount
                readonly property int shownCount: Math.min(displayCount, maxVisible)
                readonly property bool suppressLayoutAnim: panel.suppressLayoutAnim

                implicitHeight: displayCount === 0
                    ? panel.emptyNotifHeight
                    : (notifRepeater.itemAt(0) ? notifRepeater.itemAt(0).height : 64)
                      + Math.max(0, shownCount - 1) * peekHeight

                Repeater {
                    id: notifRepeater
                    model: panel.visibleNotifications

                    delegate: Item {
                        id: cardWrapper

                        required property var modelData
                        required property int index

                        visible: panel.open && index < notifStack.maxVisible

                        z: notifStack.maxVisible - index

                        x: index * notifStack.widthInset
                        y: index * notifStack.peekHeight
                        width: contentColumn.width - (index * notifStack.widthInset * 2)
                        height: card.height
                        opacity: 1.0 - (index * 0.18)

                        Rectangle {
                            id: card
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: cardContent.implicitHeight + 28
                            radius: 0
                            clip: true
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
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                    margins: 14
                                }
                                spacing: 4

                                Text {
                                    width: card.width - 28
                                    text: cardWrapper.modelData.appName
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: card.width - 28
                                    text: cardWrapper.modelData.summary
                                    color: Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: cardWrapper.modelData.body !== ""
                                    width: card.width - 28
                                    text: cardWrapper.modelData.body
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.8)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
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

            // Empty row so GRAIN / size flags sit on resin, not on the card.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: panel.notifChromeClearance + 8
            }
        }

        CornerFrame {
            open: panel.open
            duration: panel.openFadeMs
            showTopRule: true
            topRuleLabel: "CONTROL"
        }

        MarginRules {
            topRight: Theme.name || "theme"
            bottomLeft: "GRAIN " + Number(Theme.grainOpacity).toFixed(2)
            bottomRight: panel.panelWidth + " × AUTO"
        }

        GrainOverlay {}
    }
}
