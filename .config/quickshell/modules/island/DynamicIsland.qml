pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickIsland

// Open TO:DOs:
// - [ ] Fix timer component to call a pop up upon completion/start
// - [ ] Explore charging pop up for laptops

PanelWindow {
    id: island

    property var assignedScreen: null

    readonly property var resolvedScreen: { 
        const pref = assignedScreen;
        const all = Quickshell.screens;
        if (!all.length)
            return null;    
        if (!pref)
            return all[0];  
        const name = pref.name;
        for (let i = 0; i < all.length; i++) {  
            if (all[i].name === name)
                return all[i];
        }   
        return all[0];  
    }   

    screen: resolvedScreen ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    Component {
        id: notificationActivityComp
        QuickIsland.NotificationActivity {}
    }

    readonly property Component notificationActivityComponent: notificationActivityComp

    readonly property int islandPadding: 12
    readonly property int compactShellWidth: 148
    readonly property int compactShellHeight: 36
    readonly property int barReservedHeight: 21
    readonly property int displayTopGap: 1
    readonly property int shellRadius: Theme.islandShellRadius
    readonly property int standardShellWidth: Theme.islandShellWidth
    readonly property int standardShellHeight: Theme.islandShellHeight
    readonly property int hoverOverflow: 4
    readonly property int maxPreviewHeight: 280
    readonly property int previewInset: Theme.islandPreviewInset
    readonly property color shellFill: Qt.rgba(0.015, 0.015, 0.018, 0.985)
    readonly property color shellBorder: Qt.rgba(1, 1, 1, 0.085)
    readonly property color shellBorderHovered: Qt.rgba(1, 1, 1, 0.15)

    readonly property int activationHeight: 1
    property bool bodyHovered: false
    readonly property int animScaleIn: Perf.msHalf(100)
    readonly property int animScaleOut: Perf.msHalf(90)
    readonly property int animExpand: Perf.msHalf(170)
    readonly property int animFade: Perf.msHalf(80)

    property string islandState: "idle"
    property real targetWidth: standardShellWidth
    property real targetHeight: standardShellHeight

    readonly property bool pillShown: islandState !== "idle"
    readonly property bool chromeVisible: pillShown

    anchors {
        top: true
    }
    margins {
        // Counter the bar's 18 px height + 3 px top gap, then leave one
        // physical pixel between the island and the display edge.
        top: displayTopGap - barReservedHeight
    }

    implicitWidth: chromeVisible ? targetWidth + hoverOverflow * 2 : 160
    implicitHeight: chromeVisible ? targetHeight + hoverOverflow : activationHeight
    exclusiveZone: 0
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: true

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:island"

    Component.onCompleted: Qt.callLater(() => island._restoreFromService())

    function _restoreFromService() {
        const act = QuickIsland.DynamicIslandService.currentActivity;
        if (!act)
            return;
        if (island.islandState === "idle") {
            island.islandState = "pill-in";
            return;
        }
        if (island.islandState === "visible" || island.islandState === "pill-in")
            island._resyncVisibleContent();
    }

    function _resyncVisibleContent() {
        island._applyTargetSize();
        if (!contentLoader.active)
            contentLoader.active = true;
        if (!contentLoader.item)
            return;
        island._applyActivityToLoader();
        island._syncPillGeometry(island._isLargePreview());
        island._revealContent();
    }

    Connections {
        target: QuickIsland.DynamicIslandService
        function onExitRequested() {
            island.islandState = "contracting";
        }
        function onOsdBurstUpdated() {
            island._applyActivityToLoader();
        }
        function onShellLayoutChanged() {
            island._syncPillGeometry(true);
        }
        function onCurrentActivityChanged() {
            const act = QuickIsland.DynamicIslandService.currentActivity;
            if (act !== null && island.islandState === "idle") {
                island.islandState = "pill-in";
            } else if (act !== null
                       && island.islandState !== "contracting") {
                island._swapActivityInPlace();
            } else {
                island._applyActivityToLoader();
            }
        }
    }

    Connections {
        target: Theme
        function onIslandPreviewInsetChanged() {
            if (island.islandState === "visible" || island.islandState === "pill-in")
                island._resyncVisibleContent();
        }
        function onIslandPreviewContentWidthChanged() {
            if (island.islandState === "visible" || island.islandState === "pill-in")
                island._resyncVisibleContent();
        }
    }

    function _isLargePreview() {
        const act = QuickIsland.DynamicIslandService.currentActivity;
        if (!act)
            return false;
        const t = act.data?.activityType;
        return t === "screenshot" || t === "recording" || t === "recordPicker";
    }

    function _previewOuterPad() {
        return island.previewInset * 2 + pillShape.strokeWidth * 2;
    }

    function _resolveTargetSize() {
        const width = standardShellWidth;
        if (_isLargePreview() && contentLoader.item) {
            const pad = _previewOuterPad();
            const innerH = contentLoader.item.implicitHeight || standardShellHeight;
            return {
                width:  width,
                height: Math.min(maxPreviewHeight,
                    Math.max(standardShellHeight, innerH + pad))
            };
        }
        return { width: width, height: standardShellHeight };
    }

    function _applyTargetSize() {
        const size = _resolveTargetSize();
        island.targetWidth = size.width;
        island.targetHeight = size.height;
    }

    function _syncPillGeometry(animateHeight) {
        const prevH = pill.height;
        _applyTargetSize();
        pill.width = targetWidth;
        // Snap preview height — animating while thumbnail loads clips the bottom.
        if (_isLargePreview()) {
            pill.height = targetHeight;
            return;
        }
        if (animateHeight && Math.abs(prevH - targetHeight) > 1
                && !pillHeightAnim.running) {
            pillHeightAnim.from = prevH;
            pillHeightAnim.to = targetHeight;
            pillHeightAnim.start();
        } else {
            pill.height = targetHeight;
        }
    }

    function _swapActivityInPlace() {
        _pillInDone = false;
        _loaderReady = false;
        _layoutHookedActivityId = "";
        contentLoader.opacity = 0;
        contentLoader.active = false;
        contentLoader.active = true;
        island.islandState = "pill-in";
    }

    function _beginContract() {
        pillShowInAnim.stop();
        pillScaleInAnim.stop();
        contentOpacityInAnim.stop();
        contentOpacityOutAnim.stop();
        pillShowOutAnim.stop();
        pillScaleOutAnim.stop();
        contentLoader.opacity = 0;
        if (island.animScaleOut <= 0) {
            pill.showOpacity = 0;
            pill.showScale = 0.96;
            island._finishPillOut();
        } else {
            pillShowOutAnim.from = pill.showOpacity;
            pillShowOutAnim.to = 0;
            pillShowOutAnim.start();
            pillScaleOutAnim.from = pill.showScale;
            pillScaleOutAnim.start();
        }
    }

    onIslandStateChanged: {
        switch (islandState) {

        case "pill-in":
            _pillInDone = false;
            _loaderReady = false;
            _layoutHookedActivityId = "";
            island._applyTargetSize();
            contentLoader.active = false;
            pill.width = island.compactShellWidth;
            pill.height = island.compactShellHeight;
            contentLoader.opacity = 0;
            contentLoader.active = true;
            if (animScaleIn <= 0) {
                pill.showOpacity = 1;
                pill.showScale = 1;
                _onPillInDone();
            } else {
                pill.showOpacity = 0;
                pill.showScale = 0.96;
                pillScaleInAnim.start();
                pillShowInAnim.start();
            }
            break;

        case "expanding":
            island._applyTargetSize();
            if (animExpand <= 0) {
                pill.width = island.targetWidth;
                pill.height = island.targetHeight;
                islandState = "visible";
            } else {
                pillExpandHeightAnim.start();
                pillExpandWidthAnim.start();
            }
            break;

        case "visible":
            _resyncVisibleContent();
            break;

        case "contracting":
            island._beginContract();
            break;

        case "idle":
            pillScaleOutAnim.stop();
            contentLoader.active = false;
            contentLoader.opacity = 0;
            pill.width = island.compactShellWidth;
            pill.height = island.compactShellHeight;
            pill.showOpacity = 0;
            pill.showScale = 0.96;
            break;
        }
    }

    Item {
        id: pill

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        width: island.targetWidth
        height: island.targetHeight
        opacity: showOpacity
        scale: showScale * hoverScale
        transformOrigin: Item.Top

        property real showOpacity: 0
        property real showScale: 0.96
        property real hoverScale: island.bodyHovered && island.islandState === "visible" ? 1.015 : 1

        Behavior on hoverScale {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        readonly property color pillStrokeColor: {
            const d = QuickIsland.DynamicIslandService.currentActivity?.data ?? {};
            return (d.urgency === 2)
                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.55)
                : (island.bodyHovered ? island.shellBorderHovered : island.shellBorder)
        }

        QuickIsland.IslandPillShape {
            anchors.fill: parent
            anchors.topMargin: 2
            outerRadius: island.shellRadius
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.rgba(0, 0, 0, 0.32)
        }

        QuickIsland.IslandPillShape {
            id: pillShape
            anchors.fill: parent
            outerRadius: island.shellRadius
            strokeWidth: 1
            strokeColor: pill.pillStrokeColor
            fillColor: island.shellFill

            Behavior on strokeColor {
                enabled: Perf.animationsEnabled
                ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
            }
        }

        Item {
            id: pillFace
            anchors.fill: parent
            anchors.margins: pillShape.strokeWidth
            clip: true

            HoverHandler {
                onHoveredChanged: island.bodyHovered = hovered
            }

            Loader {
                id: contentLoader
                anchors.fill: parent
                anchors.leftMargin: island._isLargePreview() ? island.previewInset : Theme.islandShellHMargin
                anchors.rightMargin: island._isLargePreview() ? island.previewInset : Theme.islandShellHMargin
                anchors.topMargin: island._isLargePreview() ? island.previewInset : island.islandPadding
                anchors.bottomMargin: island._isLargePreview() ? island.previewInset : island.islandPadding
                active: false
                opacity: 0
                asynchronous: false

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
        }
    }

    property bool _pillInDone: false
    property bool _loaderReady: false
    property string _layoutHookedActivityId: ""

    function _revealContent() {
        contentOpacityInAnim.stop();
        contentOpacityOutAnim.stop();
        contentLoader.opacity = 1;
    }

    function _hookPreviewLayout(actId) {
        const item = contentLoader.item;
        if (!item || !actId || item.previewHeight === undefined)
            return;
        if (island._layoutHookedActivityId === actId)
            return;
        island._layoutHookedActivityId = actId;
        item.previewHeightChanged.connect(() => {
            QuickIsland.DynamicIslandService.shellLayoutChanged();
        });
    }

    function _tryAdvanceToExpanding() {
        if (_pillInDone && _loaderReady) {
            _pillInDone = false;
            _loaderReady = false;
            _revealContent();
            islandState = "expanding";
        }
    }
    function _onPillInDone() {
        _pillInDone = true;
        _tryAdvanceToExpanding();
    }
    function _onLoaderReady() {
        if (islandState === "pill-in") {
            _loaderReady = true;
            _tryAdvanceToExpanding();
            return;
        }
        if (islandState === "expanding") {
            island._applyTargetSize();
            pill.height = island.targetHeight;
            if (animExpand <= 0) {
                pill.width = island.targetWidth;
                islandState = "visible";
            } else if (!pillExpandWidthAnim.running) {
                pillExpandWidthAnim.start();
            }
            return;
        }
        if (islandState === "visible") {
            island._applyActivityToLoader();
            island._syncPillGeometry(true);
            island._revealContent();
        }
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
            island._hookPreviewLayout(act?.id || "");
            return;
        }

        if (d.activityType === "recording" || item.videoPath !== undefined) {
            item.videoPath = d.videoPath || "";
            item.activityId = act?.id || "";
            island._hookPreviewLayout(act?.id || "");
            return;
        }

        if (d.activityType === "recordPicker") {
            item.activityId = act?.id || "";
            return;
        }

        if (d.activityType === "osd") {
            item.kind = d.kind || "volume";
            item.icon = d.icon || "󰕾";
            item.valueLabel = d.valueLabel || "";
            item.progress = d.progress ?? 0;
            return;
        }

        if (d.activityType === "timer")
            return;

        item.appName = d.appName || "";
        const line = (d.summary || d.body || "").trim();
        item.summary = line || "New notification";
    }

    function _finishPillOut() {
        pill.showOpacity = 0;
        pill.showScale = 0.96;
        QuickIsland.DynamicIslandService.popCurrent();
        const next = QuickIsland.DynamicIslandService.currentActivity;
        if (next === null) {
            island.islandState = "idle";
        } else {
            island.islandState = "pill-in";
        }
    }

    NumberAnimation {
        id: pillShowInAnim
        target: pill
        property: "showOpacity"
        from: 0
        to: 1
        duration: island.animScaleIn
        easing.type: Easing.OutCubic
        onFinished: island._onPillInDone()
    }

    NumberAnimation {
        id: pillScaleInAnim
        target: pill
        property: "showScale"
        from: 0.96
        to: 1
        duration: island.animScaleIn
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: pillExpandWidthAnim
        target: pill
        property: "width"
        to: island.targetWidth
        duration: island.animExpand
        easing.type: Easing.OutCubic
        onFinished: island.islandState = "visible"
    }

    NumberAnimation {
        id: pillExpandHeightAnim
        target: pill
        property: "height"
        to: island.targetHeight
        duration: island.animExpand
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: contentOpacityInAnim
        target: contentLoader
        property: "opacity"
        from: 0
        to: 1
        duration: island.animFade
        easing.type: Easing.OutQuad
    }

    NumberAnimation {
        id: contentOpacityOutAnim
        target: contentLoader
        property: "opacity"
        from: 1
        to: 0
        duration: island.animFade
        easing.type: Easing.InQuad
    }

    NumberAnimation {
        id: pillHeightAnim
        target: pill
        property: "height"
        duration: island.animExpand
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: pillShowOutAnim
        target: pill
        property: "showOpacity"
        duration: island.animScaleOut
        easing.type: Easing.InCubic
        onFinished: island._finishPillOut()
    }

    NumberAnimation {
        id: pillScaleOutAnim
        target: pill
        property: "showScale"
        to: 0.96
        duration: island.animScaleOut
        easing.type: Easing.InCubic
    }
}
