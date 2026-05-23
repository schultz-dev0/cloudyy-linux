pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickIsland

PanelWindow {
    id: island

    // Defined here (not shell.qml) so Loader instances resolve Theme via island import chain.
    readonly property Component notificationActivityComponent: notificationActivityComp
    Component {
        id: notificationActivityComp
        QuickIsland.NotificationActivity {}
    }

    // ── Tunables ──────────────────────────────────────────────────────────────
    // islandPadding: space between the pill edge and the content inside it.
    // Every activity's implicitWidth/implicitHeight is the CONTENT size.
    // The pill becomes (implicitWidth + islandPadding*2) × (implicitHeight + islandPadding*2).
    readonly property int islandPadding: 10

    // pillWidth / pillHeight: size of the tiny pill during pill-in and pill-out.
    readonly property int pillWidth:  120
    readonly property int pillHeight:  28

    // pillRadius: border-radius of the pill. Keep high for fully rounded ends.
    readonly property int pillRadius:  20

    // Must match Bar.qml (topGap + barHeight).
    readonly property int barHeight:   40
    readonly property int barTopGap:    6

    // Pixels between bar bottom and pill top (added to window margins.top). Keep >= 0.
    property int belowBarGap: -45

    // ── State ─────────────────────────────────────────────────────────────────
    property string islandState: "idle" 

    // Computed target size for the expanded pill. Read from content after it loads.
    property real targetWidth:  pillWidth
    property real targetHeight: pillHeight

    // ── Window setup ─────────────────────────────────────────────────────────
    // Window top = bar bottom + belowBarGap (do not use negative pill margins — they clip).
    anchors.top: true
    margins {
        top: barHeight + barTopGap + belowBarGap
    }

    implicitWidth:  pill.width
    implicitHeight: pill.height

    exclusiveZone: 0
    color:         "transparent"

    // Hide the window entirely when idle. Keeps it out of compositor hit-testing.
    visible: islandState !== "idle"

    WlrLayershell.layer:     WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:island"

    // ── Service connection ────────────────────────────────────────────────────
    Connections {
        target: QuickIsland.DynamicIslandService
        function onExitRequested() {
            island.islandState = "contracting";
        }
        function onCurrentActivityChanged() {
            const act = QuickIsland.DynamicIslandService.currentActivity;
            if (island.islandState === "idle" && act !== null) {
                island.islandState = "pill-in";
            } else if (act !== null
                       && (island.islandState === "visible" || island.islandState === "expanding")) {
                contentLoader.active = false;
                island.islandState = "pill-in";
            } else {
                island._applyActivityToLoader();
            }
        }
    }

    // ── State machine driver ──────────────────────────────────────────────────
    onIslandStateChanged: {
        switch (islandState) {

        case "pill-in":
            // Activate the loader NOW so it loads while the pill animates in.
            _pillInDone  = false;
            _loaderReady = false;
            contentLoader.active = false;
            pill.width = island.pillWidth;
            pill.height = island.pillHeight;
            contentLoader.opacity = 0;
            contentLoader.active = true;
            pill.scale = 0;
            pillScaleInAnim.start();
            break;

        case "expanding":
            // Read content's natural size. The Loader item fills the island
            // minus islandPadding on each side, so content declares its own
            // implicitWidth/implicitHeight and the island sizes to match.
            island.targetWidth  = contentLoader.item.implicitWidth  + island.islandPadding * 2;
            island.targetHeight = contentLoader.item.implicitHeight + island.islandPadding * 2;
            pillExpandWidthAnim.start();
            pillExpandHeightAnim.start();
            break;

        case "visible":
            contentLoader.opacity = 1;
            contentOpacityInAnim.start();
            break;

        case "contracting":
            contentOpacityOutAnim.start();
            pillContractWidthAnim.start();
            pillContractHeightAnim.start();
            break;

        case "pill-out":
            pillScaleOutAnim.start();
            break;

        case "idle":
            contentLoader.active = false;
            contentLoader.opacity = 0;
            pill.width = island.pillWidth;
            pill.height = island.pillHeight;
            pill.scale = 0;
            break;
        }
    }

    // ── Pill ──────────────────────────────────────────────────────────────────
    Rectangle {
        id: pill

        anchors {
            top:                 parent.top
            horizontalCenter:    parent.horizontalCenter
        }

        // width/height start at pillWidth/pillHeight; state machine animates them.
        width:  island.pillWidth
        height: island.pillHeight
        radius: island.pillRadius
        scale:  0

        // Color: check urgency from current activity's data.
        color: {
            const d = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
            return (d.urgency === 2)
                ? Qt.rgba(Theme.error_container.r, Theme.error_container.g, Theme.error_container.b, 0.95)
                : Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.96)
        }

        border.width: 1
        border.color: {
            const d = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
            return (d.urgency === 2)
                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.7)
                : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
        }

        // ── Content loader ────────────────────────────────────────────────────
        Loader {
            id: contentLoader
            anchors.fill:    parent
            anchors.margins: island.islandPadding
            active:          false
            opacity:         0  

            sourceComponent: {
                const act = QuickIsland.DynamicIslandService.currentActivity;
                return act?.contentComponent ?? island.notificationActivityComponent;
            }

            onStatusChanged: {
                if (status === Loader.Ready) {
                    island._applyActivityToLoader();
                    island._onLoaderReady();
                }
            }
        }

        // ── +N pending badge ──────────────────────────────────────────────────
        // Shows how many activities are queued behind the current one.
        // Safe to overlap because all activities are left-aligned inside the pill.
        Text {
            visible: QuickIsland.DynamicIslandService.pendingCount > 0
                  && island.islandState === "visible"
            text:   "+" + QuickIsland.DynamicIslandService.pendingCount
            color:  Qt.rgba(Theme.on_surface_variant.r,
                            Theme.on_surface_variant.g,
                            Theme.on_surface_variant.b, 0.8)
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 9

            anchors.right:          parent.right
            anchors.rightMargin:    island.islandPadding
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Race-condition guard ──────────────────────────────────────────────────
    // pill-in scale anim and Loader load are both async. We advance to "expanding"
    // only when BOTH have finished. These flags track each side.
    property bool _pillInDone:   false
    property bool _loaderReady:  false

    function _tryAdvanceToExpanding() {
        if (_pillInDone && _loaderReady) {
            _pillInDone  = false;
            _loaderReady = false;
            islandState  = "expanding";
        }
    }
    function _onPillInDone() {
        _pillInDone = true;
        _tryAdvanceToExpanding();
    }
    function _onLoaderReady() {
        if (islandState !== "pill-in") return;  // guard stale signals
        _loaderReady = true;
        _tryAdvanceToExpanding();
    }

    function _applyActivityToLoader() {
        if (!contentLoader.item)
            return;
        const act = QuickIsland.DynamicIslandService.currentActivity;
        const d = act?.data ?? {};
        const item = contentLoader.item;

        if (d.activityType === "screenshot" || item.imagePath !== undefined) {
            item.imagePath = d.imagePath || "";
            item.activityId = act?.id || "";
            return;
        }

        if (d.activityType === "recording" || item.videoPath !== undefined) {
            item.videoPath = d.videoPath || "";
            item.activityId = act?.id || "";
            return;
        }

        if (d.activityType === "recordPicker") {
            item.activityId = act?.id || "";
            return;
        }

        item.appName = d.appName || "";
        const line = (d.summary || d.body || "").trim();
        item.summary = line || "New notification";
    }

    // ── Animations ────────────────────────────────────────────────────────────

    // pill-in: tiny pill springs into existence
    NumberAnimation {
        id:       pillScaleInAnim
        target:   pill
        property: "scale"
        from:     0; to: 1
        duration: 150
        easing.type: Easing.OutBack
        easing.overshoot: 1.5
        onFinished: island._onPillInDone()
    }

    // expanding: pill grows to content size
    NumberAnimation {
        id:       pillExpandWidthAnim
        target:   pill
        property: "width"
        to:       island.targetWidth
        duration: 250
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id:       pillExpandHeightAnim
        target:   pill
        property: "height"
        to:       island.targetHeight
        duration: 250
        easing.type: Easing.OutCubic
        onFinished: island.islandState = "visible"   // height anim is authoritative
    }

    // visible: content fades in
    NumberAnimation {
        id:       contentOpacityInAnim
        target:   contentLoader
        property: "opacity"
        from:     0; to: 1
        duration: 120
        easing.type: Easing.OutQuad
    }

    // contracting: content fades out, pill shrinks back to tiny pill
    NumberAnimation {
        id:       contentOpacityOutAnim
        target:   contentLoader
        property: "opacity"
        from:     1; to: 0
        duration: 120
        easing.type: Easing.InQuad
    }
    NumberAnimation {
        id:       pillContractWidthAnim
        target:   pill
        property: "width"
        to:       island.pillWidth
        duration: 200
        easing.type: Easing.InCubic
    }
    NumberAnimation {
        id:       pillContractHeightAnim
        target:   pill
        property: "height"
        to:       island.pillHeight
        duration: 200
        easing.type: Easing.InCubic
        onFinished: island.islandState = "pill-out" 
    }

    // pill-out: tiny pill shrinks to nothing
    NumberAnimation {
        id:       pillScaleOutAnim
        target:   pill
        property: "scale"
        from:     1; to: 0
        duration: 150
        easing.type: Easing.InBack
        easing.overshoot: 1.5
        onFinished: {
            QuickIsland.DynamicIslandService.popCurrent();
            if (QuickIsland.DynamicIslandService.currentActivity === null)
                island.islandState = "idle";
            else
                island.islandState = "pill-in";
        }
    }
}
