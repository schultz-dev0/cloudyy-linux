pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickIsland
import "IslandStatePolicy.js" as Policy

PanelWindow {
    id: island

    property var assignedScreen: null
    property bool transientDismissing: false
    property var persistentSnapshot: null

    readonly property var resolvedScreen: {
        const screens = Quickshell.screens;
        if (!screens.length)
            return null;

        const ownedName = QuickIsland.IslandState.openingScreenName;
        const preferredName = ownedName || assignedScreen?.name || "";
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === preferredName)
                return screens[i];
        }
        return screens[0];
    }
    readonly property var activeTransient:
        QuickIsland.DynamicIslandService.currentActivity
    readonly property string transientPresentation: activeTransient
        ? Policy.transientPresentation(activeTransient.data?.activityType,
                                       QuickIsland.IslandState.pinned)
        : "none"
    readonly property bool transientActive: transientPresentation === "full"
    readonly property var inlineNotification: transientPresentation === "inline"
        ? activeTransient.data : null
    readonly property bool largePreview: {
        const type = QuickIsland.DynamicIslandService.currentActivity?.data?.activityType;
        return type === "screenshot" || type === "recording" || type === "recordPicker";
    }
    readonly property int persistentWidth: QuickIsland.IslandState.mode === "resting"
        ? (timerPill.active ? Theme.islandTimerRestWidth : Theme.islandRestWidth)
        : Theme.islandCarouselWidth
    readonly property int persistentHeight: {
        if (QuickIsland.IslandState.expanded)
            return Theme.islandExpandedMaxHeight;
        return QuickIsland.IslandState.mode === "resting"
            ? Theme.islandRestHeight : Theme.islandCarouselHeight;
    }
    readonly property int transientHeight: {
        if (!largePreview || !contentLoader.item)
            return Theme.islandShellHeight;
        const contentHeight = contentLoader.item.implicitHeight || Theme.islandShellHeight;
        return Math.min(280, Math.max(
            Theme.islandShellHeight,
            contentHeight + Theme.islandPreviewInset * 2 + pillShape.strokeWidth * 2));
    }
    readonly property real targetWidth: transientActive
        ? Theme.islandShellWidth : persistentWidth
    readonly property real targetHeight: transientActive
        ? transientHeight : persistentHeight
    readonly property real lowerRadius: QuickIsland.IslandState.mode === "resting"
        && !transientActive ? Theme.islandRestLowerRadius : Theme.islandOpenLowerRadius
    readonly property real effectiveLowerRadius: Math.min(
        lowerRadius, width / 2, height / 2)

    screen: resolvedScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    anchors.top: true
    implicitWidth: Math.min(targetWidth, screen ? screen.width - 16 : targetWidth)
    implicitHeight: Math.min(targetHeight, screen ? screen.height - 40 : targetHeight)
    // No exclusiveZone assignment: it would flip exclusionMode back to Normal
    // and let the bar's reserved area push the island off the physical top edge.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: true
    mask: Region {
        Region {
            x: Theme.islandShoulderRadius
            width: Math.max(0, island.width - Theme.islandShoulderRadius * 2)
            height: Theme.islandShoulderRadius
        }
        Region {
            y: Theme.islandShoulderRadius
            width: island.width
            height: Math.max(0, island.height
                - Theme.islandShoulderRadius - island.effectiveLowerRadius)
        }
        Region {
            x: island.effectiveLowerRadius
            y: Math.max(Theme.islandShoulderRadius,
                island.height - island.effectiveLowerRadius)
            width: Math.max(0, island.width - island.effectiveLowerRadius * 2)
            height: Math.min(island.effectiveLowerRadius,
                island.height - Theme.islandShoulderRadius)
        }
        Region {
            y: island.height - island.effectiveLowerRadius * 2
            width: island.effectiveLowerRadius * 2
            height: island.effectiveLowerRadius * 2
            shape: RegionShape.Ellipse
        }
        Region {
            x: island.width - island.effectiveLowerRadius * 2
            y: island.height - island.effectiveLowerRadius * 2
            width: island.effectiveLowerRadius * 2
            height: island.effectiveLowerRadius * 2
            shape: RegionShape.Ellipse
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:island"
    WlrLayershell.keyboardFocus: QuickIsland.IslandState.keyboardRequested
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Perf.geometryMs(to < from
                ? Theme.islandCloseDuration : Theme.islandOpenDuration)
            easing.type: to < from ? Easing.InCubic : Easing.OutCubic
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Perf.geometryMs(to < from
                ? Theme.islandCloseDuration
                : (QuickIsland.IslandState.expanded
                    ? Theme.islandExpandDuration : Theme.islandOpenDuration))
            easing.type: to < from
                ? Easing.InCubic
                : (QuickIsland.IslandState.expanded ? Easing.OutQuart : Easing.OutCubic)
        }
    }

    Component {
        id: notificationActivityComponent
        QuickIsland.NotificationActivity {}
    }

    Connections {
        target: QuickIsland.DynamicIslandService

        function onCurrentActivityChanged() {
            island.transientDismissing = false;
            island._syncTransientPresentation();
        }

        function onTransientPresented(activity) {
            island._syncTransientPresentation();
        }

        function onTransientUpdated(activity) {
            if (island.activeTransient?.id !== activity?.id)
                return;
            if (!QuickIsland.DynamicIslandService._finishingActivityId) {
                dismissTimer.stop();
                island.transientDismissing = false;
            }
            island._syncTransientPresentation();
        }

        function onTransientFinished(activityId) {
            if (island.activeTransient?.id !== activityId)
                return;
            island._restorePersistentState();
            if (island.transientActive) {
                island.transientDismissing = true;
                dismissTimer.restart();
            } else {
                QuickIsland.DynamicIslandService.popCurrent();
            }
        }

        function onOsdBurstUpdated() {
            island._applyActivityToLoader();
        }

        function onShellLayoutChanged() {
            island._applyActivityToLoader();
        }
    }

    Connections {
        target: contentLoader.item
        ignoreUnknownSignals: true

        function onPreviewHeightChanged() {
            QuickIsland.DynamicIslandService.shellLayoutChanged();
        }
    }

    Timer {
        id: dismissTimer
        interval: Perf.opacityMs(Theme.islandOpacityDuration)
        repeat: false
        onTriggered: QuickIsland.DynamicIslandService.popCurrent()
    }

    Item {
        id: shell
        anchors.fill: parent

        QuickIsland.IslandPillShape {
            anchors {
                fill: parent
                topMargin: 2
            }
            shoulderRadius: Theme.islandShoulderRadius
            lowerRadius: island.effectiveLowerRadius
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.rgba(0, 0, 0, 0.18)
        }

        QuickIsland.IslandPillShape {
            id: pillShape
            // Extend 1px above the window's own top edge so the border's
            // top stroke falls outside the surface and gets clipped away —
            // a border on all four sides reads as a separate floating card;
            // dropping just the top one (which sits flush on the screen
            // edge) is what sells "attached to the bezel" over "hovering
            // below it." Left/right/bottom stay bordered as before.
            anchors {
                fill: parent
                topMargin: -1
            }
            shoulderRadius: Theme.islandShoulderRadius
            lowerRadius: island.effectiveLowerRadius
            strokeWidth: 1
            strokeColor: Theme.islandBorder
            fillColor: Theme.islandSurface
        }

        Item {
            id: persistentContent
            anchors.fill: parent
            enabled: !island.transientActive
            opacity: island.transientActive ? 0 : 1

            QuickIsland.IslandCarousel {
                anchors.fill: parent
                visible: QuickIsland.IslandState.mode !== "resting"
                inlineActivity: island.inlineNotification
            }

            QuickIsland.TimerRestingPill {
                id: timerPill
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Perf.opacityMs(Theme.islandOpacityDuration)
                    easing.type: Easing.OutQuad
                }
            }
        }

        Loader {
            id: contentLoader
            property var loadedSourceComponent: null

            anchors.fill: parent
            anchors.leftMargin: island.largePreview
                ? Theme.islandPreviewInset : Theme.islandShellHMargin
            anchors.rightMargin: island.largePreview
                ? Theme.islandPreviewInset : Theme.islandShellHMargin
            anchors.topMargin: island.largePreview ? Theme.islandPreviewInset : 12
            anchors.bottomMargin: island.largePreview ? Theme.islandPreviewInset : 12
            active: island.transientActive
            asynchronous: false
            opacity: active && status === Loader.Ready && !island.transientDismissing ? 1 : 0
            sourceComponent: {
                const activity = QuickIsland.DynamicIslandService.currentActivity;
                return island._expectedActivityComponent(activity);
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Perf.opacityMs(Theme.islandOpacityDuration)
                    easing.type: Easing.OutQuad
                }
            }

            onSourceComponentChanged: loadedSourceComponent = null
            onStatusChanged: {
                if (status !== Loader.Ready)
                    loadedSourceComponent = null;
            }
            onLoaded: {
                loadedSourceComponent = sourceComponent;
                island._applyActivityToLoader();
            }
        }

        HoverHandler {
            enabled: !island.transientActive
            onHoveredChanged: {
                if (hovered)
                    QuickIsland.IslandState.beginHover(island.screen?.name ?? "");
                else
                    QuickIsland.IslandState.endHover();
            }
        }

        TapHandler {
            // Only the resting (collapsed) pill needs "click anywhere to
            // open" — once the island is already open, this whole-shell
            // handler still fires on every click, including clicks on
            // buttons inside the carousel/expanded content (e.g. Timer's
            // "+ New timer"), and pin() unconditionally ends with
            // mode = "pinned", clobbering whatever that button's own
            // handler just set (like activateCurrent()'s mode = "expanded")
            // in the same click. Scoping it to resting removes the race
            // without losing anything — hover and pinned both already
            // auto-collapse the same way now, so there's nothing left for
            // a background click to usefully do once it's open.
            enabled: !island.transientActive && QuickIsland.IslandState.mode === "resting"
            onTapped: QuickIsland.IslandState.pin(island.screen?.name ?? "")
        }
    }

    onTransientPresentationChanged: _syncTransientPresentation()

    function _capturePersistentState() {
        if (island.persistentSnapshot)
            return;
        island.persistentSnapshot = {
            mode: QuickIsland.IslandState.mode,
            currentPage: QuickIsland.IslandState.currentPage,
            rememberedPage: QuickIsland.IslandState.rememberedPage,
            openingScreenName: QuickIsland.IslandState.openingScreenName
        };
    }

    function _restorePersistentState() {
        const snapshot = island.persistentSnapshot;
        if (!snapshot)
            return;
        QuickIsland.IslandState.mode = snapshot.mode;
        QuickIsland.IslandState.currentPage = snapshot.currentPage;
        QuickIsland.IslandState.rememberedPage = snapshot.rememberedPage;
        QuickIsland.IslandState.openingScreenName = snapshot.openingScreenName;
        island.persistentSnapshot = null;
    }

    function _syncTransientPresentation() {
        const activity = island.activeTransient;
        if (!activity)
            return;
        if (island.transientActive) {
            island._capturePersistentState();
        } else {
            island.persistentSnapshot = null;
        }
        if ((activity.data?.urgency ?? 0) === 2)
            QuickIsland.DynamicIslandService.holdCurrent(activity.id);
        else
            QuickIsland.DynamicIslandService.resumeCurrent(activity.id);
        island._applyActivityToLoader();
    }

    function _expectedActivityComponent(activity) {
        return activity?.contentComponent ?? notificationActivityComponent;
    }

    function _applyActivityToLoader() {
        const activity = QuickIsland.DynamicIslandService.currentActivity;
        const expectedComponent = island._expectedActivityComponent(activity);
        if (!activity || !contentLoader.item
                || contentLoader.status !== Loader.Ready
                || contentLoader.sourceComponent !== expectedComponent
                || contentLoader.loadedSourceComponent !== expectedComponent)
            return;
        const data = activity?.data ?? {};
        const item = contentLoader.item;

        if (data.activityType === "screenshot") {
            if (item.imagePath === undefined)
                return;
            item.imagePath = data.imagePath || "";
            item.activityId = activity?.id || "";
            return;
        }

        if (data.activityType === "recording") {
            if (item.videoPath === undefined)
                return;
            item.videoPath = data.videoPath || "";
            item.activityId = activity?.id || "";
            return;
        }

        if (data.activityType === "recordPicker") {
            if (item.activityId === undefined)
                return;
            item.activityId = activity?.id || "";
            return;
        }

        if (data.activityType === "osd") {
            if (item.kind === undefined)
                return;
            item.kind = data.kind || "volume";
            item.icon = data.icon || "󰕾";
            item.valueLabel = data.valueLabel || "";
            item.progress = data.progress ?? 0;
            return;
        }

        if (data.activityType === "timer") {
            if (item.completedTimer === undefined)
                return;
            item.completedTimer = data.completedTimer ?? null;
            return;
        }

        if (item.appName === undefined || item.summary === undefined)
            return;
        item.appName = data.appName || "";
        const line = (data.summary || data.body || "").trim();
        item.summary = line || "New notification";
    }
}
