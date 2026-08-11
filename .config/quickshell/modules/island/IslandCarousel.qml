pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "." as QuickIsland

FocusScope {
    id: root

    property var inlineActivity: null
    readonly property string currentPage: QuickIsland.IslandState.currentPage
    readonly property var pageOrder: ["notifications", "calendar", "timer", "media", "system"]
    readonly property int currentIndex: Math.max(0, pageOrder.indexOf(currentPage))
    property real trackpadDelta: 0

    // All 5 pages are kept alive (not Loader-based) so state survives
    // cycling, but only the current page and its immediate neighbors are
    // ever actually on/near screen during a slide — painting the other
    // 2-3 full page trees every animation frame for no visible benefit is
    // the likely source of the reported lag, so skip rendering them.
    function isPageNear(index) {
        return Math.abs(index - root.currentIndex) <= 1;
    }

    focus: root.enabled && QuickIsland.IslandState.keyboardRequested
    clip: true

    Keys.onLeftPressed: event => {
        if (QuickIsland.IslandState.expanded)
            return;
        QuickIsland.IslandState.cycle(-1);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        if (QuickIsland.IslandState.expanded)
            return;
        QuickIsland.IslandState.cycle(1);
        event.accepted = true;
    }
    Keys.onReturnPressed: event => {
        QuickIsland.IslandState.activateCurrent();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        QuickIsland.IslandState.activateCurrent();
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        QuickIsland.IslandState.handleEscape();
        event.accepted = true;
    }
    Keys.onPressed: event => {
        if (!QuickIsland.IslandState.expanded
                || !(event.modifiers & Qt.ControlModifier))
            return;
        if (event.key === Qt.Key_PageUp) {
            QuickIsland.IslandState.cycle(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            QuickIsland.IslandState.cycle(1);
            event.accepted = true;
        }
    }

    Item {
        id: viewport
        anchors {
            fill: parent
            topMargin: 14
            bottomMargin: 14
        }
        clip: true

        // A plain Item, not Row: Row/Column/Grid positioners exclude
        // visible:false children from layout and repack the rest, which
        // breaks the fixed-slot assumption "pageRow.x = -currentIndex *
        // viewport.width" depends on (each page must stay at its own
        // index * viewport.width forever, regardless of visibility).
        Item {
            id: pageRow
            x: -root.currentIndex * viewport.width
            width: viewport.width * root.pageOrder.length
            height: viewport.height

            // Every Text in this repo uses renderType: NativeRendering for
            // crisp static text, but native-rendered glyphs are hinted to
            // the pixel grid and get re-hinted every frame as an item
            // translates — that per-frame re-hint is what reads as "rough"
            // next to the expand animation (which resizes the window
            // instead of sliding dense text across it). Caching this
            // subtree into one texture and sliding the texture instead
            // sidesteps the re-hinting entirely, and is cheaper to boot
            // (one blit instead of re-walking the whole page tree/frame).
            layer.enabled: true

            Behavior on x {
                NumberAnimation {
                    duration: Perf.geometryMs(220)
                    easing.type: Easing.OutCubic
                }
            }

            QuickIsland.NotificationsPage {
                x: 0 * viewport.width
                width: viewport.width
                height: viewport.height
                visible: root.isPageNear(0)
                opacity: root.currentPage === "notifications" ? 1 : 0.24
                onActivateRequested: QuickIsland.IslandState.activateCurrent()
            }

            QuickIsland.CalendarPage {
                x: 1 * viewport.width
                width: viewport.width
                height: viewport.height
                visible: root.isPageNear(1)
                opacity: root.currentPage === "calendar" ? 1 : 0.24
                onActivateRequested: QuickIsland.IslandState.activateCurrent()
            }

            QuickIsland.TimerPage {
                x: 2 * viewport.width
                width: viewport.width
                height: viewport.height
                visible: root.isPageNear(2)
                opacity: root.currentPage === "timer" ? 1 : 0.24
                onActivateRequested: QuickIsland.IslandState.activateCurrent()
            }

            QuickIsland.MediaPage {
                x: 3 * viewport.width
                width: viewport.width
                height: viewport.height
                visible: root.isPageNear(3)
                opacity: root.currentPage === "media" ? 1 : 0.24
                onActivateRequested: QuickIsland.IslandState.activateCurrent()
            }

            QuickIsland.SystemOverviewPage {
                x: 4 * viewport.width
                width: viewport.width
                height: viewport.height
                visible: root.isPageNear(4)
                opacity: root.currentPage === "system" ? 1 : 0.24
                onActivateRequested: QuickIsland.IslandState.activateCurrent()
            }
        }
    }

    WheelHandler {
        enabled: !QuickIsland.IslandState.expanded
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const pixelX = event.pixelDelta.x;
            const pixelY = event.pixelDelta.y;
            const hasPixelDelta = pixelX !== 0 || pixelY !== 0;

            if (hasPixelDelta) {
                if (Math.abs(pixelX) > Math.abs(pixelY))
                    root.trackpadDelta += pixelX;
                else
                    root.trackpadDelta = 0;
            } else if (Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)) {
                root.trackpadDelta += event.angleDelta.x / 3;
            } else if (event.angleDelta.y !== 0) {
                root.trackpadDelta = 0;
                QuickIsland.IslandState.cycle(event.angleDelta.y < 0 ? 1 : -1);
            }

            if (Math.abs(root.trackpadDelta) >= 40) {
                QuickIsland.IslandState.cycle(root.trackpadDelta < 0 ? 1 : -1);
                root.trackpadDelta = 0;
            }
            event.accepted = true;
        }
    }

    HoverHandler {
        id: carouselHover
    }

    Text {
        anchors {
            left: parent.left
            leftMargin: 5
            verticalCenter: parent.verticalCenter
        }
        z: 2
        text: "<"
        color: Theme.islandOnSurface
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        font.weight: Font.Bold
        renderType: Text.NativeRendering
        opacity: carouselHover.hovered ? 0.82 : 0.18

        Behavior on opacity {
            NumberAnimation {
                duration: Perf.opacityMs(100)
                easing.type: Easing.OutQuad
            }
        }

        TapHandler {
            onTapped: QuickIsland.IslandState.cycle(-1)
        }
    }

    Text {
        anchors {
            right: parent.right
            rightMargin: 5
            verticalCenter: parent.verticalCenter
        }
        z: 2
        text: ">"
        color: Theme.islandOnSurface
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        font.weight: Font.Bold
        renderType: Text.NativeRendering
        opacity: carouselHover.hovered ? 0.82 : 0.18

        Behavior on opacity {
            NumberAnimation {
                duration: Perf.opacityMs(100)
                easing.type: Easing.OutQuad
            }
        }

        TapHandler {
            onTapped: QuickIsland.IslandState.cycle(1)
        }
    }

    QuickIsland.IslandInlineActivity {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        z: 3
        visible: root.inlineActivity !== null
        appName: root.inlineActivity?.appName ?? ""
        summary: root.inlineActivity?.summary ?? ""
        icon: root.inlineActivity?.icon ?? ""
        urgency: root.inlineActivity?.urgency ?? 0
    }
}
