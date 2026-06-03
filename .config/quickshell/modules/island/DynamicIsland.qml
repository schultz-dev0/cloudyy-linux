pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickIsland

PanelWindow {
    id: island

    readonly property Component notificationActivityComponent: notificationActivityComp
    Component {
        id: notificationActivityComp
        QuickIsland.NotificationActivity {}
    }

    readonly property int islandPadding: 10
    readonly property int pillWidth: 120
    readonly property int pillHeight: 28
    readonly property int pillRadius: 20
    readonly property int barHeight: 40
    readonly property int barTopGap: 6
    property int belowBarGap: -45

    // Fixed overlay size — avoids resizing the layer surface every animation frame.
    readonly property int maxIslandWidth: 272
    readonly property int maxIslandHeight: 196

    readonly property int animScaleIn: Perf.msHalf(100)
    readonly property int animScaleOut: Perf.msHalf(90)
    readonly property int animExpand: Perf.msHalf(170)
    readonly property int animContract: Perf.msHalf(140)
    readonly property int animFade: Perf.msHalf(80)

    property string islandState: "idle"
    property real targetWidth: pillWidth
    property real targetHeight: pillHeight

    anchors.top: true
    margins {
        top: barHeight + barTopGap + belowBarGap
    }

    implicitWidth: maxIslandWidth
    implicitHeight: maxIslandHeight
    exclusiveZone: 0
    color: "transparent"
    visible: islandState !== "idle"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:island"

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
                island._swapActivityInPlace();
            } else {
                island._applyActivityToLoader();
            }
        }
    }

    function _swapActivityInPlace() {
        _pillInDone = false;
        _loaderReady = false;
        contentLoader.opacity = 0;
        contentLoader.active = false;
        contentLoader.active = true;
        if (islandState === "visible")
            islandState = "expanding";
    }

    onIslandStateChanged: {
        switch (islandState) {

        case "pill-in":
            _pillInDone = false;
            _loaderReady = false;
            contentLoader.active = false;
            pill.width = island.pillWidth;
            pill.height = island.pillHeight;
            contentLoader.opacity = 0;
            contentLoader.active = true;
            if (animScaleIn <= 0) {
                pill.scale = 1;
                _onPillInDone();
            } else {
                pill.scale = 0;
                pillScaleInAnim.start();
            }
            break;

        case "expanding":
            island.targetWidth = Math.min(
                contentLoader.item.implicitWidth + island.islandPadding * 2,
                maxIslandWidth);
            island.targetHeight = Math.min(
                contentLoader.item.implicitHeight + island.islandPadding * 2,
                maxIslandHeight);
            pill.height = island.targetHeight;
            if (animExpand <= 0) {
                pill.width = island.targetWidth;
                islandState = "visible";
            } else {
                pillExpandWidthAnim.start();
            }
            break;

        case "visible":
            if (animFade <= 0) {
                contentLoader.opacity = 1;
            } else {
                contentOpacityInAnim.start();
            }
            break;

        case "contracting":
            pill.height = island.pillHeight;
            if (animFade <= 0) {
                contentLoader.opacity = 0;
            } else {
                contentOpacityOutAnim.start();
            }
            if (animContract <= 0) {
                pill.width = island.pillWidth;
                islandState = "pill-out";
            } else {
                pillContractWidthAnim.start();
            }
            break;

        case "pill-out":
            if (animScaleOut <= 0) {
                pill.scale = 0;
                _finishPillOut();
            } else {
                pillScaleOutAnim.start();
            }
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

    Rectangle {
        id: pill

        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
        }

        width: island.pillWidth
        height: island.pillHeight
        radius: island.pillRadius
        scale: 0

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

        Loader {
            id: contentLoader
            anchors.fill: parent
            anchors.margins: island.islandPadding
            active: false
            opacity: 0
            asynchronous: true

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

        Text {
            visible: QuickIsland.DynamicIslandService.pendingCount > 0
                  && island.islandState === "visible"
            text: "+" + QuickIsland.DynamicIslandService.pendingCount
            color: Qt.rgba(Theme.on_surface_variant.r,
                            Theme.on_surface_variant.g,
                            Theme.on_surface_variant.b, 0.8)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            anchors.right: parent.right
            anchors.rightMargin: island.islandPadding
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    property bool _pillInDone: false
    property bool _loaderReady: false

    function _tryAdvanceToExpanding() {
        if (_pillInDone && _loaderReady) {
            _pillInDone = false;
            _loaderReady = false;
            islandState = "expanding";
        }
    }
    function _onPillInDone() {
        _pillInDone = true;
        _tryAdvanceToExpanding();
    }
    function _onLoaderReady() {
        if (islandState !== "pill-in" && islandState !== "expanding")
            return;
        if (islandState === "pill-in") {
            _loaderReady = true;
            _tryAdvanceToExpanding();
            return;
        }
        if (islandState === "expanding") {
            island.targetWidth = Math.min(
                contentLoader.item.implicitWidth + island.islandPadding * 2,
                maxIslandWidth);
            island.targetHeight = Math.min(
                contentLoader.item.implicitHeight + island.islandPadding * 2,
                maxIslandHeight);
            pill.height = island.targetHeight;
            if (animExpand <= 0) {
                pill.width = island.targetWidth;
                islandState = "visible";
            } else if (!pillExpandWidthAnim.running) {
                pillExpandWidthAnim.start();
            }
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

    function _finishPillOut() {
        QuickIsland.DynamicIslandService.popCurrent();
        if (QuickIsland.DynamicIslandService.currentActivity === null)
            island.islandState = "idle";
        else
            island.islandState = "pill-in";
    }

    NumberAnimation {
        id: pillScaleInAnim
        target: pill
        property: "scale"
        from: 0
        to: 1
        duration: island.animScaleIn
        easing.type: Easing.OutCubic
        onFinished: island._onPillInDone()
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
        id: pillContractWidthAnim
        target: pill
        property: "width"
        to: island.pillWidth
        duration: island.animContract
        easing.type: Easing.InCubic
        onFinished: island.islandState = "pill-out"
    }

    NumberAnimation {
        id: pillScaleOutAnim
        target: pill
        property: "scale"
        from: 1
        to: 0
        duration: island.animScaleOut
        easing.type: Easing.InCubic
        onFinished: island._finishPillOut()
    }
}
