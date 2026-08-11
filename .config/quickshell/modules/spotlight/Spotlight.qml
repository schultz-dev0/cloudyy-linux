pragma ComponentBehavior: Bound

// modules/spotlight/Spotlight.qml — overlay UI (Spotlight search + Command Center browse)
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../calculator/backend" as CalcBackend
import "../currency/backend" as CurrencyBackend
import "../time/backend" as TimeBackend
import "../commandcenter/applibrary"
import "../commandcenter/wallpapers"

PanelWindow {
    id: root

    readonly property var svc: SpotlightService

    CalcBackend.Calculator {
        id: calculator
    }

    CurrencyBackend.CurrencyConverter {
        id: currencyConverter
    }

    TimeBackend.TimeCalculator {
        id: timeCalculator
    }

    readonly property string currencyFetchScript: Qt.resolvedUrl("../currency/backend/fetch_rate.sh").toString().replace("file://", "")
    readonly property string webSearchUrl: "https://duckduckgo.com/?q="
    readonly property int screenHeight: screen?.height ?? 0

    anchors {
        top: svc.anchor === "top" || svc.anchor === "left" || svc.anchor === "right"
        bottom: svc.anchor === "bottom"
        left: svc.anchor === "left" || svc.anchor === "top" || svc.anchor === "bottom"
        right: svc.anchor === "right" || svc.anchor === "top" || svc.anchor === "bottom"
    }

    margins {
        top: svc.anchor === "top" ? svc.topMargin : 0
        bottom: svc.anchor === "bottom" ? svc.topMargin : 0
        left: svc.anchor === "left" ? 24 : 0
        right: svc.anchor === "right" ? 24 : 0
    }

    readonly property bool panelActive: svc.visible || svc.closing

    implicitWidth: panelActive ? svc.overlayWidth : 0
    implicitHeight: panelActive
        ? contentPanel.implicitHeight + (svc.anchor === "top" || svc.anchor === "bottom" ? svc.topMargin : 0)
        : 0
    visible: panelActive
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.keyboardGrab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        svc.launch(cmd);
    }

    function showWebSearch() {
        launch(["xdg-open", webSearchUrl + encodeURIComponent(svc.query)]);
        svc.close();
    }

    function activateIndex(idx) {
        if (idx < 0)
            return;
        if (idx < svc.results.length) {
            svc.activateIndex(idx);
            return;
        }
        if (svc.mode === "spotlight" || svc.mode === "command")
            showWebSearch();
    }

    function selectionTop(index) {
        let y = 0;
        if (bodyCol.isBrowseMode && svc.browseStack.length > 0)
            y += bodyCol.breadcrumbHeight;
        return y + index * bodyCol.rowHeight;
    }

    function activeFlickable() {
        return bodyCol.isBrowseMode ? browseFlick : resultsFlick;
    }

    function ensureSelectionVisible() {
        if (svc.selectedIndex < 0)
            return;
        const flick = activeFlickable();
        if (!flick.visible || flick.height <= 0)
            return;
        const top = selectionTop(svc.selectedIndex);
        const bottom = top + bodyCol.rowHeight;
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        let y = flick.contentY;
        if (top < y)
            y = top;
        else if (bottom > y + flick.height)
            y = bottom - flick.height;
        flick.contentY = Math.max(0, Math.min(maxY, y));
    }

    function moveSelection(delta) {
        const max = bodyCol.displayCount() - 1;
        if (max < 0)
            return;

        let next;
        if (svc.selectedIndex < 0)
            next = delta > 0 ? 0 : max;
        else {
            next = svc.selectedIndex + delta;
            if (next < 0)
                next = max;
            else if (next > max)
                next = 0;
        }

        svc.selectedIndex = next;
        ensureSelectionVisible();
    }

    function buildTimeEntry() {
        if (!timeCalculator.isTimeExpression(svc.query))
            return null;
        const seconds = timeCalculator.evaluate(svc.query);
        if (seconds === null)
            return null;
        return {
            type: "time",
            expression: svc.query,
            result: timeCalculator.formatResult(seconds),
            subtitle: timeCalculator.formatSubtitle(seconds)
        };
    }

    function buildCalcEntry() {
        if (!calculator.isMathExpression(svc.query))
            return null;
        const value = calculator.evaluate(svc.query);
        if (calculator.hasError || value === null)
            return null;
        return {
            type: "calculator",
            expression: svc.query,
            result: calculator.formatResult(value)
        };
    }

    function inlineResultMatches(entry, candidate) {
        return entry.type === candidate.type
            && (entry.expression ?? "") === (candidate.expression ?? "")
            && (entry.result ?? "") === (candidate.result ?? "");
    }

    function prependInlineResults() {
        const timeEntry = buildTimeEntry();
        const calcEntry = buildCalcEntry();
        const currencyQuery = currencyConverter.isCurrencyQuery(svc.query);
        const currencyEntry = currencyQuery
            ? svc.results.find(r => r.type === "currency" && (r.expression ?? "") === svc.query)
            : null;
        const withoutInline = svc.results.filter(r =>
            r.type !== "time" && r.type !== "calculator" && r.type !== "currency");
        const next = [];
        if (currencyEntry)
            next.push(currencyEntry);
        if (timeEntry)
            next.push(timeEntry);
        if (calcEntry)
            next.push(calcEntry);

        if (next.length === 0) {
            if (withoutInline.length !== svc.results.length)
                svc.results = withoutInline;
            return;
        }

        const prefix = svc.results.slice(0, next.length);
        if (prefix.length === next.length
            && prefix.every((entry, i) => inlineResultMatches(entry, next[i]))
            && svc.results.length === next.length + withoutInline.length)
            return;

        svc.results = next.concat(withoutInline);
    }

    function upsertCurrencyEntry(entry) {
        const rest = svc.results.filter(r => r.type !== "currency");
        svc.results = [entry, ...rest];
    }

    function clearCurrencyResults() {
        currencyDebounce.stop();
        currencyProc.running = false;
        currencyProc.fetchQuery = "";
        if (svc.results.some(r => r.type === "currency"))
            svc.results = svc.results.filter(r => r.type !== "currency");
    }

    function showCurrencyPending(parsed) {
        const cached = currencyConverter.convertCached(parsed.amount, parsed.from, parsed.to);
        if (cached) {
            upsertCurrencyEntry({
                type: "currency",
                expression: svc.query,
                result: currencyConverter.formatResult(parsed.amount, parsed.from, parsed.to, cached.converted, cached.date),
                subtitle: currencyConverter.formatSubtitle(parsed.amount, parsed.from, parsed.to, cached.rate, cached.date, "refreshing…")
            });
            return;
        }
        upsertCurrencyEntry({
            type: "currency",
            expression: svc.query,
            result: `${currencyConverter.formatAmount(parsed.amount)} ${parsed.from} → ${parsed.to}`,
            subtitle: "Looking up…"
        });
    }

    function startCurrencyFetch(parsed, querySnapshot) {
        currencyProc.running = false;
        currencyProc.fetchQuery = querySnapshot;
        currencyProc.command = [
            "bash", root.currencyFetchScript,
            parsed.amount.toString(),
            parsed.from,
            parsed.to
        ];
        currencyProc.running = true;
    }

    function syncCurrencyForQuery() {
        const parsed = currencyConverter.parseQuery(svc.query);
        if (!parsed) {
            clearCurrencyResults();
            return;
        }
        showCurrencyPending(parsed);
        currencyDebounce.restart();
    }

    Timer {
        id: currencyDebounce
        interval: 180
        repeat: false
        onTriggered: {
            const parsed = currencyConverter.parseQuery(svc.query);
            if (!parsed)
                return;
            root.startCurrencyFetch(parsed, svc.query);
        }
    }

    Process {
        id: currencyProc
        property string fetchQuery: ""
        stdout: StdioCollector {
            id: currencyCollector
            onStreamFinished: {
                if (svc.query !== currencyProc.fetchQuery)
                    return;
                const text = currencyCollector.text.trim();
                if (!text)
                    return;
                try {
                    const data = JSON.parse(text);
                    const parsed = currencyConverter.parseQuery(svc.query);
                    if (!parsed)
                        return;
                    if (data.error) {
                        root.upsertCurrencyEntry({
                            type: "currency",
                            expression: svc.query,
                            result: `${currencyConverter.formatAmount(parsed.amount)} ${parsed.from} → ${parsed.to}`,
                            subtitle: String(data.error)
                        });
                        return;
                    }
                    if (Number.isFinite(data.rate))
                        currencyConverter.rememberRate(parsed.from, parsed.to, data.rate, data.date || "");
                    const extra = data.stale || data.cached ? "cached" : "";
                    root.upsertCurrencyEntry({
                        type: "currency",
                        expression: svc.query,
                        result: currencyConverter.formatResult(parsed.amount, parsed.from, parsed.to, data.converted, data.date),
                        subtitle: currencyConverter.formatSubtitle(parsed.amount, parsed.from, parsed.to, data.rate, data.date, extra)
                    });
                } catch (_) {}
            }
        }
    }

    Connections {
        target: svc
        function onQueryChanged() {
            if (svc.visible && searchInput.text !== svc.query)
                searchInput.text = svc.query;

            prependInlineResults();
            root.syncCurrencyForQuery();
        }
        function onResultsChanged() {
            prependInlineResults();
        }
        function onBrowseStackChanged() {
            browseFlick.contentY = 0;
        }
        function onSelectedIndexChanged() {
            Qt.callLater(() => root.ensureSelectionVisible());
        }
        function onRequestFocus() {
            searchInput.forceActiveFocus();
        }
        function onVisibleChanged() {
            if (svc.visible) {
                searchInput.text = svc.query;
                Qt.callLater(() => searchInput.forceActiveFocus());
            } else {
                searchInput.text = "";
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: svc.close()
    }

    Item {
        id: contentPanel
        width: svc.overlayWidth
        implicitHeight: searchBar.height + bodyCol.listBodyHeight
        opacity: svc.closing ? 0 : 1

        Behavior on opacity {
            enabled: Perf.animationsEnabled
            NumberAnimation {
                duration: Perf.msHalf(140)
                easing.type: Easing.OutCubic
            }
        }

        anchors.horizontalCenter: svc.anchor === "top" || svc.anchor === "bottom" ? parent.horizontalCenter : undefined
        anchors.verticalCenter: svc.anchor === "left" || svc.anchor === "right" ? parent.verticalCenter : undefined
        anchors.top: svc.anchor === "top" ? parent.top : undefined
        anchors.bottom: svc.anchor === "bottom" ? parent.bottom : undefined
        anchors.left: svc.anchor === "left" ? parent.left : undefined
        anchors.right: svc.anchor === "right" ? parent.right : undefined

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.glassPanelRadius
            color: Theme.glassShell
            border.color: Theme.glassPanelBorder
            border.width: 1
            antialiasing: true
        }

        Column {
            id: bodyCol
            width: parent.width

            Item {
                id: searchBar
                width: parent.width
                height: 40

                Text {
                    id: searchIcon
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: "⌕"
                    color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.55)
                    font.pixelSize: 16
                    font.family: "JetBrainsMono Nerd Font"
                }

                TextInput {
                    id: searchInput
                    anchors {
                        left: searchIcon.right
                        leftMargin: 10
                        right: parent.right
                        rightMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    height: 22
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.family: "JetBrainsMono Nerd Font"
                    verticalAlignment: TextInput.AlignVCenter
                    topPadding: Math.round((height - font.pixelSize) / 2)
                    bottomPadding: topPadding
                    selectByMouse: true
                        onTextChanged: {
                            if (svc.query !== text)
                                svc.query = text;
                        }
                        Keys.onEscapePressed: {
                            if (!svc.browseBack())
                                svc.close();
                            event.accepted = true;
                        }
                        Keys.onUpPressed: {
                            root.moveSelection(-1);
                            event.accepted = true;
                        }
                        Keys.onDownPressed: {
                            root.moveSelection(1);
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: {
                            if (svc.selectedIndex >= 0)
                                root.activateIndex(svc.selectedIndex);
                            event.accepted = true;
                        }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    visible: svc.query.length > 0 || svc.results.length > 0
                    color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)
                }
            }

            readonly property int rowHeight: 46
            readonly property int breadcrumbHeight: 36
            readonly property int listCapHeight: {
                if (root.screenHeight > 0)
                    return Math.max(0, Math.round(root.screenHeight * 0.75) - searchBar.height);
                return 560;
            }
            readonly property bool isBrowseMode: svc.mode === "command" && svc.query.length === 0 && !svc.showingKeybinds
            readonly property bool resultsListVisible: !isBrowseMode && (svc.results.length > 0 || svc.query.length > 0)
            readonly property int listBodyHeight: isBrowseMode
                ? (browseFlick.height)
                : (resultsListVisible ? resultsFlick.height : 0)

            function listViewHeight(contentCol) {
                const h = Math.ceil(contentCol.implicitHeight);
                if (h <= 0)
                    return 0;
                return Math.min(listCapHeight, h);
            }

            function displayCount() {
                if (isBrowseMode)
                    return Math.max(svc.results.length, 1);
                let n = svc.results.length;
                if ((svc.mode === "spotlight" || svc.mode === "command") && svc.query.length > 0)
                    n += 1;
                return Math.max(n, 1);
            }

            Flickable {
                id: resultsFlick
                width: parent.width
                height: bodyCol.resultsListVisible ? bodyCol.listViewHeight(resultsCol) : 0
                visible: bodyCol.resultsListVisible
                clip: true
                contentHeight: resultsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                function clampScroll() {
                    const maxY = Math.max(0, contentHeight - height);
                    if (contentY > maxY)
                        contentY = maxY;
                    if (contentY < 0)
                        contentY = 0;
                }
                onContentHeightChanged: clampScroll()
                onHeightChanged: clampScroll()

                Column {
                    id: resultsCol
                    width: parent.width

                    Repeater {
                        model: svc.results
                        delegate: SpotlightRow {
                            required property var modelData
                            required property int index
                            resultData: modelData.type === "command"
                                ? {
                                    type: "command",
                                    name: modelData.label,
                                    subtitle: modelData.subtitle,
                                    icon: modelData.icon,
                                    isActive: modelData.isActive === true
                                }
                                : (modelData.type === "ollama_model" || modelData.type === "package" || modelData.type === "package_action" || modelData.type === "ollama_action"
                                    ? {
                                        type: "command",
                                        name: modelData.label || modelData.name,
                                        subtitle: modelData.subtitle || "",
                                        icon: modelData.icon || (modelData.type === "package" ? "󰏖" : "󰚩")
                                    }
                                    : modelData)
                            isSelected: svc.selectedIndex >= 0 && index === svc.selectedIndex
                            rowWidth: svc.overlayWidth
                            onActivated: root.activateIndex(index)
                            onHovered: svc.selectedIndex = index
                        }
                    }

                    SpotlightRow {
                        visible: (svc.mode === "spotlight" || svc.mode === "command") && svc.query.length > 0
                        resultData: ({ type: "web", query: svc.query })
                        isSelected: svc.selectedIndex >= 0 && svc.selectedIndex === svc.results.length
                        rowWidth: svc.overlayWidth
                        onActivated: root.activateIndex(svc.results.length)
                        onHovered: svc.selectedIndex = svc.results.length
                    }
                }
            }

            Flickable {
                id: browseFlick
                width: parent.width
                height: bodyCol.isBrowseMode ? bodyCol.listViewHeight(browseCol) : 0
                visible: bodyCol.isBrowseMode
                clip: true
                contentHeight: browseCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                function clampScroll() {
                    const maxY = Math.max(0, contentHeight - height);
                    if (contentY > maxY)
                        contentY = maxY;
                    if (contentY < 0)
                        contentY = 0;
                }
                onContentHeightChanged: clampScroll()
                onHeightChanged: clampScroll()

                Column {
                    id: browseCol
                    width: parent.width

                    Text {
                        visible: svc.browseStack.length > 0
                        text: "  " + (SpotlightService.entryById(svc.currentParentId())?.label || "")
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        topPadding: 8
                        leftPadding: 8
                    }

                    Repeater {
                        model: svc.results
                        delegate: SpotlightRow {
                            required property var modelData
                            required property int index
                            resultData: modelData.type === "command"
                                ? {
                                    type: "command",
                                    name: modelData.label,
                                    subtitle: modelData.subtitle,
                                    icon: modelData.icon,
                                    isActive: modelData.isActive === true
                                }
                                : (modelData.type === "ollama_model" || modelData.type === "package" || modelData.type === "package_action" || modelData.type === "ollama_action"
                                    ? {
                                        type: "command",
                                        name: modelData.label || modelData.name,
                                        subtitle: modelData.subtitle || "",
                                        icon: modelData.icon || (modelData.type === "package" ? "󰏖" : "󰚩")
                                    }
                                    : modelData)
                            isSelected: svc.selectedIndex >= 0 && index === svc.selectedIndex
                            rowWidth: svc.overlayWidth
                            onActivated: root.activateIndex(index)
                            onHovered: svc.selectedIndex = index
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "spotlight"
        function toggle() {
            svc.toggle();
        }
        function show() {
            svc.openMode("spotlight");
        }
        function hide() {
            svc.close();
        }
        function command() {
            svc.openMode("command");
        }
        function apps() {
            AppLibraryService.open();
        }
        function wallpaper() {
            WallpaperPickerService.open();
        }
    }
}
