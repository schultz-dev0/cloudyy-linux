pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "." as QuickIsland

FocusScope {
    id: root

    required property var registry
    required property var navigationState

    property var inlineActivity: null
    property var _pages: []
    readonly property string currentPage: root.navigationState.currentPage
    readonly property var pageOrder: root._pages.map(page => page.id)
    readonly property int pageCount: pageOrder.length
    readonly property int currentIndex: Math.max(0, pageOrder.indexOf(currentPage))
    property real trackpadDelta: 0

    function _samePageStructure(nextPages) {
        if (root._pages.length !== nextPages.length)
            return false;
        for (let i = 0; i < nextPages.length; i++) {
            if (root._pages[i].id !== nextPages[i].id
                    || root._pages[i].pageComponent !== nextPages[i].pageComponent)
                return false;
        }
        return true;
    }

    function _syncPages() {
        const nextPages = root.registry.availablePages;
        if (root._samePageStructure(nextPages))
            return;
        root._pages = nextPages.map(page => ({
            id: page.id,
            pageComponent: page.pageComponent
        }));
    }

    // Keep every available page alive so local state survives cycling, but
    // only render the current page and immediate neighbors during a slide.
    function isPageNear(index) {
        return Math.abs(index - root.currentIndex) <= 1;
    }

    focus: root.enabled && root.navigationState.keyboardRequested
    clip: true

    Keys.onLeftPressed: event => {
        if (root.navigationState.expanded || root.pageCount < 2)
            return;
        root.navigationState.cycle(-1);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        if (root.navigationState.expanded || root.pageCount < 2)
            return;
        root.navigationState.cycle(1);
        event.accepted = true;
    }
    Keys.onReturnPressed: event => {
        root.navigationState.activateCurrent();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        root.navigationState.activateCurrent();
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        root.navigationState.handleEscape();
        event.accepted = true;
    }
    Keys.onPressed: event => {
        if (!root.navigationState.expanded
                || root.pageCount < 2
                || !(event.modifiers & Qt.ControlModifier))
            return;
        if (event.key === Qt.Key_PageUp) {
            root.navigationState.cycle(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root.navigationState.cycle(1);
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
            objectName: "island-page-row"
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
                    duration: Math.abs(to - from) > viewport.width * 1.5
                        ? 0 : Perf.geometryMs(220)
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                model: root._pages

                delegate: Loader {
                    id: pageLoader

                    required property int index
                    required property var modelData

                    objectName: "island-page-loader-" + modelData.id
                    x: index * viewport.width
                    width: viewport.width
                    height: viewport.height
                    active: true
                    asynchronous: false
                    visible: root.isPageNear(index)
                    opacity: root.currentPage === modelData.id ? 1 : 0.24
                    sourceComponent: modelData.pageComponent

                    Connections {
                        target: pageLoader.item
                        ignoreUnknownSignals: true
                        function onActivateRequested() {
                            root.navigationState.activateCurrent();
                        }
                    }
                }
            }
        }
    }

    WheelHandler {
        enabled: root.pageCount > 1 && !root.navigationState.expanded
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
                root.navigationState.cycle(event.angleDelta.y < 0 ? 1 : -1);
            }

            if (Math.abs(root.trackpadDelta) >= 40) {
                root.navigationState.cycle(root.trackpadDelta < 0 ? 1 : -1);
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
        visible: root.pageCount > 1
        opacity: carouselHover.hovered ? 0.82 : 0.18

        Behavior on opacity {
            NumberAnimation {
                duration: Perf.opacityMs(100)
                easing.type: Easing.OutQuad
            }
        }

        TapHandler {
            enabled: root.pageCount > 1
            onTapped: root.navigationState.cycle(-1)
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
        visible: root.pageCount > 1
        opacity: carouselHover.hovered ? 0.82 : 0.18

        Behavior on opacity {
            NumberAnimation {
                duration: Perf.opacityMs(100)
                easing.type: Easing.OutQuad
            }
        }

        TapHandler {
            enabled: root.pageCount > 1
            onTapped: root.navigationState.cycle(1)
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

    Connections {
        target: root.registry
        function onRevisionChanged() {
            root._syncPages();
        }
    }

    Component.onCompleted: root._syncPages()
}
