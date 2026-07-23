import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "../services" as S
import ".."

// Wallhaven browser: search/sort bar, results grid, load-more. Backend does
// all the network work (lib/ccd/online_wallpapers.py); this just renders
// whatever it returns and re-requests on search/sort/load-more.
Column {
    id: browser
    width: parent ? parent.width : 0
    required property var item
    property string query: ""
    property string sort: "hot"   // "hot" | "toplist" — ignored once a query is set
    property string minRes: ""    // "" | "1920x1080" | "2560x1440" | "3840x2160" — Wallhaven's "atleast" filter
    property string targetMode: "dark"   // "light" | "dark" — which wallpaper pool downloads land in
    property int page: 1
    property bool loading: false
    property bool hasMore: true
    property var results: []      // accumulates across "Load more"
    readonly property int columns: 4
    property var contextItem: null   // result the right-click menu / preview dialog targets
    property var scrollFlickable: null   // ancestor Flickable that actually scrolls (YamlPage), for infinite scroll
    padding: 14
    spacing: 10

    function findFlickableAncestor(startItem) {
        let p = startItem.parent;
        while (p) {
            if (p.contentY !== undefined && p.contentHeight !== undefined) return p;
            p = p.parent;
        }
        return null;
    }

    function maybeLoadMore() {
        const f = browser.scrollFlickable;
        if (!f || browser.loading || !browser.hasMore) return;
        if (f.contentY + f.height >= f.contentHeight - 600) {
            browser.page += 1;
            browser.doSearch(false);
        }
    }

    function doSearch(reset) {
        if (reset) { browser.page = 1; browser.results = []; browser.hasMore = true; }
        browser.loading = true;
        S.Backend.request("search_wallpapers_online",
            { query: browser.query, sort: browser.sort, page: browser.page, min_res: browser.minRes },
            function (result) {
                browser.loading = false;
                if (!result) return;
                const combined = reset ? (result.results ?? [])
                                       : browser.results.concat(result.results ?? []);
                // Wallhaven's anonymous API always returns ~23-24/page, never a
                // clean multiple of the 4-column grid — trim the ragged remainder
                // (at most 3 items) instead of leaving a half-empty last row.
                // Skipped when there isn't even one full row yet, so a narrow
                // search with few matches doesn't get hidden entirely.
                const full = combined.length < browser.columns
                    ? combined.length
                    : Math.floor(combined.length / browser.columns) * browser.columns;
                browser.results = combined.slice(0, full);
                browser.hasMore = !!result.has_more;
                // A short result set (or a tall viewport) may not leave enough
                // scrollable content to ever fire onContentYChanged again —
                // keep topping up until the page actually overflows or results
                // run out. Deferred one tick so gridWrap's height (derived from
                // browser.results) has actually recomputed first.
                Qt.callLater(browser.maybeLoadMore);
            });
    }

    Component.onCompleted: {
        doSearch(true);
        S.Backend.request("get_theme_mode", {}, function (result) {
            if (result && result.mode) browser.targetMode = result.mode;
        });
        browser.scrollFlickable = browser.findFlickableAncestor(browser);
    }

    Connections {
        target: browser.scrollFlickable
        function onContentYChanged() { browser.maybeLoadMore(); }
    }

    // Search field (own row, full width) + chip row (sort chips left, light/dark
    // target-pool chips right) below it — was one cramped row, sort chips ate
    // into the search field's width.
    Column {
        id: topBar
        width: browser.width - browser.leftPadding - browser.rightPadding
        spacing: 8

        // Item (not Row/Column), so children can anchor — wallGrid's centering
        // fix established this pattern for positioner children.
        Item {
            width: topBar.width
            height: 30

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.glass(Theme.surface_container_high, 0.7)
                TextInput {
                    id: searchInput
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textPrimary
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 }
                    onAccepted: { browser.query = text; browser.doSearch(true); }
                    Text { visible: !parent.text; text: "⌕ Search Wallhaven…"
                           anchors.verticalCenter: parent.verticalCenter
                           color: Theme.textMuted; font: parent.font }
                }
            }
        }

        Item {
            width: topBar.width
            height: 30

            // Hot/Top chips + resolution dropdown share the left side of this
            // row — Row is a positioner so a hidden sortRow (during a text
            // search) is skipped automatically and resCombo just shifts left.
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 10

                Row {
                    id: sortRow
                    spacing: 6
                    visible: searchInput.text === ""
                    Repeater {
                        model: [{ id: "hot", label: "Hot" }, { id: "toplist", label: "Top" }]
                        delegate: Rectangle {
                            required property var modelData
                            width: sortText.implicitWidth + 18; height: 30; radius: 8
                            color: browser.sort === modelData.id ? Theme.primary
                                                                  : Theme.glass(Theme.surface_container_high, 0.7)
                            Text { id: sortText; anchors.centerIn: parent; text: modelData.label
                                   color: browser.sort === modelData.id ? Theme.background : Theme.textMuted
                                   font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                            TapHandler { onTapped: { browser.sort = modelData.id; browser.doSearch(true); } }
                        }
                    }
                }

                // Resolution filter — Wallhaven's own "atleast" search param, not
                // an invented category. Always visible (unlike Hot/Top, it composes
                // with a text query on Wallhaven's side rather than being
                // overridden by it). Same ComboBox styling as RowSelect.qml.
                ComboBox {
                    id: resCombo
                    width: 100
                    readonly property var resValues: ["", "1920x1080", "2560x1440", "3840x2160"]
                    model: ["Any", "1080p+", "1440p+", "4K+"]
                    currentIndex: Math.max(0, resValues.indexOf(browser.minRes))
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                    onActivated: index => {
                        browser.minRes = resValues[index];
                        browser.doSearch(true);
                    }

                    contentItem: Text {
                        leftPadding: 8
                        text: resCombo.displayText
                        color: Theme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                    }
                    background: Rectangle {
                        implicitWidth: 100; implicitHeight: 30; radius: 8
                        color: Theme.glass(Theme.surface_container_high, 0.7)
                        border { width: 1; color: Theme.outline_variant }
                    }
                    delegate: ItemDelegate {
                        width: resCombo.width
                        highlighted: resCombo.highlightedIndex === index
                        contentItem: Text {
                            text: modelData
                            color: Theme.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
                        }
                        background: Rectangle {
                            color: highlighted ? Theme.glass(Theme.primary, 0.14) : "transparent"
                        }
                    }
                    popup: Popup {
                        y: resCombo.height
                        width: resCombo.width
                        padding: 4
                        enter: null; exit: null
                        contentItem: ListView {
                            clip: true
                            implicitHeight: contentHeight
                            model: resCombo.popup.visible ? resCombo.delegateModel : null
                            currentIndex: resCombo.highlightedIndex
                        }
                        background: Rectangle {
                            radius: 8
                            color: Theme.surface_container
                            border { width: 1; color: Theme.outline_variant }
                        }
                    }
                }
            }

            Row {
                id: modeRow
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Repeater {
                    model: [{ id: "light", label: "Light" }, { id: "dark", label: "Dark" }]
                    delegate: Rectangle {
                        required property var modelData
                        width: modeText.implicitWidth + 18; height: 30; radius: 8
                        color: browser.targetMode === modelData.id ? Theme.primary
                                                                    : Theme.glass(Theme.surface_container_high, 0.7)
                        Text { id: modeText; anchors.centerIn: parent; text: modelData.label
                               color: browser.targetMode === modelData.id ? Theme.background : Theme.textMuted
                               font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                        TapHandler { onTapped: browser.targetMode = modelData.id }
                    }
                }
            }
        }
    }

    Item {
        id: gridWrap
        width: browser.width - browser.leftPadding - browser.rightPadding
        // Hug actual content instead of reserving a fixed box (config's
        // height: 700 left dead space below short result sets — Wallhaven's
        // anonymous API caps pages at ~24 results, confirmed against the
        // live API, so there's no "fetch more" fix, only "don't over-reserve").
        height: Math.max(106, Math.ceil(browser.results.length / browser.columns) * 106)

        GridView {
            anchors.fill: parent
            // Stretch cells to exactly fill gridWrap's width (== topBar's width)
            // instead of a fixed 150px — a fixed width left a gap between the
            // last column and the search bar/chip row's right edge above it.
            cellWidth: gridWrap.width / browser.columns; cellHeight: 106
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: browser.results
            delegate: Rectangle {
                id: tile
                required property var modelData
                width: (gridWrap.width / browser.columns) - 10; height: 96; radius: 10
                color: Theme.surface_container
                border { width: 1; color: Theme.glass(Theme.outline_variant, 0.5) }

                // Same rounded-mask idiom as WallpaperGrid.qml / island/ScreenshotActivity.qml —
                // `clip: true` alone only clips to the bounding box, not to `radius`.
                Rectangle {
                    id: imageMask
                    anchors.fill: parent; anchors.margins: 2
                    radius: 8
                    color: "white"
                    opacity: 0
                    layer.enabled: true
                }
                Image {
                    anchors.fill: parent; anchors.margins: 2
                    source: tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                    sourceSize { width: 280; height: 192 }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: imageMask
                    }
                }
                Text {
                    visible: tile.modelData.resolution !== ""
                    anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                    text: tile.modelData.resolution
                    color: "white"
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 8 }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: S.Backend.request("apply_wallpaper_online", {
                        url: tile.modelData.full_url,
                        light_directory: browser.item.light_directory,
                        dark_directory: browser.item.dark_directory,
                        apply_command: browser.item.apply_command,
                        apply: true,
                        mode: browser.targetMode,
                    }, null)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: eventPoint => {
                        browser.contextItem = tile.modelData;
                        // Map into Overlay.overlay, not browser — a modal Popup
                        // renders into the window's Overlay regardless of its
                        // declared `parent`, so x/y computed relative to browser
                        // (which sits inside a scrollable Flickable) could land
                        // the *visible* menu somewhere other than where its
                        // *hit-test* region actually was, close enough to the
                        // tile that a click meant for a menu item could land on
                        // the tile's own apply-on-tap handler instead.
                        const pos = tile.mapToItem(Overlay.overlay, eventPoint.position.x, eventPoint.position.y);
                        contextMenu.x = pos.x;
                        contextMenu.y = pos.y;
                        contextMenu.open();
                    }
                }
            }
        }
    }

    // Right-click menu — mirrors the legacy GTK browser's per-result actions
    // (Open/Preview/Download were separate buttons there; a context menu here
    // since Apply already owns the plain click). One shared instance targeting
    // browser.contextItem instead of one Popup per tile.
    Popup {
        id: contextMenu
        // No explicit parent — matches previewDialog below; a modal Popup
        // renders into the window's Overlay regardless, so x/y (set via
        // mapToItem(Overlay.overlay, ...) above) need to agree with that,
        // not with browser's own (scrollable, offset) coordinate space.
        modal: true
        dim: false
        padding: 4
        enter: null; exit: null   // motion budget: no popup fade, matches RowSelect/KeybindManager
        background: Rectangle { radius: 8; color: Theme.surface_container
                                 border { width: 1; color: Theme.outline_variant } }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: [
                    { id: "preview", label: "Preview" },
                    { id: "open", label: "Open in Browser" },
                    { id: "download", label: "Download" },
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: 160; height: 26; radius: 6
                    color: menuHover.hovered ? Theme.glass(Theme.primary, 0.14) : "transparent"
                    Text { anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                           text: modelData.label; color: Theme.textPrimary
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 } }
                    HoverHandler { id: menuHover }
                    TapHandler {
                        onTapped: {
                            const target = browser.contextItem;
                            if (target) {
                                if (modelData.id === "preview") {
                                    previewDialog.visible = true;
                                } else if (modelData.id === "open") {
                                    Qt.openUrlExternally(target.page_url);
                                } else if (modelData.id === "download") {
                                    S.Backend.request("apply_wallpaper_online", {
                                        url: target.full_url,
                                        light_directory: browser.item.light_directory,
                                        dark_directory: browser.item.dark_directory,
                                        apply_command: browser.item.apply_command,
                                        apply: false,
                                        mode: browser.targetMode,
                                    }, null);
                                }
                            }
                            contextMenu.close();
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: previewDialog
        modal: true; dim: true; focus: true
        anchors.centerIn: Overlay.overlay
        padding: 4
        enter: null; exit: null
        onClosed: visible = false
        background: Rectangle { radius: 14; color: Theme.surface_container
                                 border { width: 1; color: Theme.outline_variant } }
        contentItem: Image {
            source: browser.contextItem && browser.contextItem.thumb ? "file://" + browser.contextItem.thumb : ""
            fillMode: Image.PreserveAspectFit
            // Cached search thumbnail, upscaled — same source the grid tile
            // already shows, just bigger, no extra network fetch (matches the
            // legacy GTK Preview dialog, which also just re-showed its cache).
            width: Math.min(720, sourceSize.width || 720)
            height: Math.min(500, sourceSize.height || 500)
        }
    }

    Item {
        id: footer
        width: browser.width - browser.leftPadding - browser.rightPadding
        height: 30

        // Infinite scroll (browser.maybeLoadMore, triggered off the ancestor
        // Flickable's contentY) replaced the old "Load more" button — this is
        // now just a loading/empty indicator.
        Text {
            visible: browser.loading
            anchors.centerIn: parent
            text: "Loading…"
            color: Theme.textMuted
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        }
        Text {
            visible: !browser.loading && browser.results.length === 0
            anchors.centerIn: parent
            text: "No results"
            color: Theme.textMuted
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        }
    }
}
