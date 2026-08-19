import QtQuick
import "IslandStatePolicy.js" as Policy

QtObject {
    id: state

    required property var registry

    property string mode: "resting"
    property string currentPage: ""
    property string rememberedPage: ""
    property string openingScreenName: ""
    readonly property bool pinned: mode === "pinned" || mode === "expanded"
    readonly property bool expanded: mode === "expanded"
    readonly property bool keyboardRequested: pinned

    property string _hoverScreenName: ""
    readonly property Timer _hoverIntentTimer: Timer {
        interval: 120
        repeat: false
        onTriggered: {
            if (state.mode !== "resting" || !state._repairNavigation())
                return;
            state.openingScreenName = state._hoverScreenName;
            state.mode = "hover";
        }
    }
    readonly property Timer _collapseGraceTimer: Timer {
        interval: 280
        repeat: false
        onTriggered: {
            if (state.mode !== "resting")
                state.hide();
        }
    }

    signal controlCenterRequested
    signal systemOverviewRequested
    signal activationFailed(string target)
    signal closingRequested

    function _availablePageIds() {
        return state.registry.availablePageIds;
    }

    function _orderedPageIds() {
        return state.registry.integrations.map(integration => integration.id);
    }

    function _repairNavigation() {
        const availableIds = state._availablePageIds();
        if (availableIds.length === 0) {
            state._hoverIntentTimer.stop();
            state._collapseGraceTimer.stop();
            if (state.mode !== "resting")
                state.mode = "resting";
            state.openingScreenName = "";
            if (state.currentPage !== "") {
                state.currentPage = "";
            }
            return false;
        }
        const repaired = Policy.repairNavigation(
            state.currentPage, state.rememberedPage,
            state._orderedPageIds(), availableIds);
        const pageChanged = repaired.currentPage !== state.currentPage
            || repaired.rememberedPage !== state.rememberedPage;
        if (pageChanged) {
            state.rememberedPage = repaired.rememberedPage;
            state.currentPage = repaired.currentPage;
        }
        return true;
    }

    function beginHover(screenName) {
        _collapseGraceTimer.stop();
        if (mode !== "resting" || _availablePageIds().length === 0)
            return;
        _hoverScreenName = screenName;
        _hoverIntentTimer.restart();
    }

    function endHover() {
        _hoverIntentTimer.stop();
        if (mode !== "resting")
            _collapseGraceTimer.restart();
    }

    function pin(screenName) {
        _hoverIntentTimer.stop();
        _collapseGraceTimer.stop();
        if (!_repairNavigation())
            return false;
        if (screenName)
            openingScreenName = screenName;
        mode = "pinned";
        return true;
    }

    function toggle(screenName) {
        if (pinned)
            hide();
        else
            show(screenName);
    }

    function show(screenName) {
        if (!pin(screenName))
            return false;
        return true;
    }

    function hide() {
        _hoverIntentTimer.stop();
        _collapseGraceTimer.stop();
        closingRequested();
        mode = "resting";
        openingScreenName = "";
    }

    function completeExternalActivation(target, success) {
        if (success)
            hide();
        else
            activationFailed(target);
    }

    function showPage(pageId, screenName) {
        if (_availablePageIds().length === 0
                || _availablePageIds().indexOf(pageId) === -1)
            return false;
        currentPage = pageId;
        rememberedPage = pageId;
        if (!pin(screenName))
            return false;
        return true;
    }

    function cycle(delta) {
        const availableIds = _availablePageIds();
        if (availableIds.length === 0)
            return false;
        currentPage = Policy.cyclePage(currentPage, delta, availableIds);
        rememberedPage = currentPage;
        return true;
    }

    function activateCurrent() {
        const integration = state.registry.integrationById(currentPage);
        const activation = Policy.activationForPage(integration);
        if (activation === "expand") {
            mode = "expanded";
        } else if (activation === "controlCenter") {
            mode = "pinned";
            controlCenterRequested();
        } else if (activation === "systemOverview") {
            mode = "pinned";
            systemOverviewRequested();
        }
    }

    function restorePersistentSnapshot(snapshot) {
        if (!snapshot)
            return false;
        currentPage = snapshot.currentPage;
        rememberedPage = snapshot.rememberedPage;
        if (!_repairNavigation())
            return false;
        mode = Policy.restoreAfterTransient(snapshot.mode);
        openingScreenName = mode === "resting" ? "" : snapshot.openingScreenName;
        return true;
    }

    function handleEscape() {
        const target = Policy.escapeTarget(mode);
        if (target === "resting")
            hide();
        else
            mode = target;
    }

    readonly property Connections _registryConnections: Connections {
        target: state.registry
        function onRevisionChanged() {
            state._repairNavigation();
        }
    }

    Component.onCompleted: state._repairNavigation()
}
