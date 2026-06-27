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

    implicitWidth: svc.overlayWidth
    implicitHeight: svc.visible ? contentPanel.implicitHeight + (svc.anchor === "top" || svc.anchor === "bottom" ? svc.topMargin : 0) : 0
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
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

    function prependTimeResult() {
        const withoutTime = svc.results.filter(r => r.type !== "time");
        if (!timeCalculator.isTimeExpression(svc.query)) {
            if (withoutTime.length !== svc.results.length)
                svc.results = withoutTime;
            return;
        }
        const seconds = timeCalculator.evaluate(svc.query);
        if (seconds === null) {
            if (withoutTime.length !== svc.results.length)
                svc.results = withoutTime;
            return;
        }
        const entry = {
            type: "time",
            expression: svc.query,
            result: timeCalculator.formatResult(seconds),
            subtitle: timeCalculator.formatSubtitle(seconds)
        };
        svc.results = [entry, ...withoutTime];
    }

    function prependCalcCurrency() {
        prependTimeResult();

        const withoutCalc = svc.results.filter(r => r.type !== "calculator");
        if (!calculator.isMathExpression(svc.query)) {
            if (withoutCalc.length !== svc.results.length)
                svc.results = withoutCalc;
            return;
        }
        const value = calculator.evaluate(svc.query);
        if (calculator.hasError || value === null) {
            if (withoutCalc.length !== svc.results.length)
                svc.results = withoutCalc;
            return;
        }
        const entry = {
            type: "calculator",
            expression: svc.query,
            result: calculator.formatResult(value)
        };
        svc.results = [entry, ...withoutCalc];
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
                    if (data.error)
                        return;
                    const parsed = currencyConverter.parseQuery(svc.query);
                    if (!parsed)
                        return;
                    const entry = {
                        type: "currency",
                        expression: svc.query,
                        result: currencyConverter.formatResult(parsed.amount, parsed.from, parsed.to, data.converted, data.date),
                        subtitle: currencyConverter.formatSubtitle(parsed.amount, parsed.from, parsed.to, data.rate, data.date)
                    };
                    svc.results = [entry, ...svc.results.filter(r => r.type !== "currency")];
                } catch (_) {}
            }
        }
    }

    Connections {
        target: svc
        function onQueryChanged() {
            if (svc.visible && searchInput.text !== svc.query)
                searchInput.text = svc.query;

            prependTimeResult();

            const parsed = currencyConverter.parseQuery(svc.query);
            if (!parsed)
                return;
            currencyProc.running = false;
            currencyProc.fetchQuery = svc.query;
            currencyProc.command = [
                "bash", root.currencyFetchScript,
                parsed.amount.toString(),
                parsed.from,
                parsed.to
            ];
            currencyProc.running = true;
        }
        function onResultsChanged() {
            prependCalcCurrency();
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
                const screens = Quickshell.screens;
                if (screens.length > 0)
                    return Math.round(screens[0].height * 0.58);
                return 560;
            }
            readonly property bool isBrowseMode: svc.mode === "command" && svc.query.length === 0
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
            if (svc.visible && svc.mode === "spotlight")
                svc.close();
            else
                svc.openMode("spotlight");
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
