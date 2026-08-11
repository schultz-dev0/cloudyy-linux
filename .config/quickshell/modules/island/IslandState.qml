pragma Singleton

import QtQuick
import "IslandStatePolicy.js" as Policy

QtObject {
    id: state

    property string mode: "resting"
    property string currentPage: "notifications"
    property string rememberedPage: "notifications"
    property string openingScreenName: ""
    readonly property bool pinned: mode === "pinned" || mode === "expanded"
    readonly property bool expanded: mode === "expanded"
    readonly property bool keyboardRequested: pinned

    property string _hoverScreenName: ""
    readonly property Timer _hoverIntentTimer: Timer {
        interval: 120
        repeat: false
        onTriggered: {
            if (state.mode !== "resting")
                return;
            state.openingScreenName = state._hoverScreenName;
            state.currentPage = state.rememberedPage;
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

    function beginHover(screenName) {
        _collapseGraceTimer.stop();
        if (mode !== "resting")
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
        if (mode === "resting") {
            openingScreenName = screenName;
            currentPage = rememberedPage;
        }
        mode = "pinned";
    }

    function toggle(screenName) {
        if (pinned)
            hide();
        else
            show(screenName);
    }

    function show(screenName) {
        pin(screenName);
    }

    function hide() {
        _hoverIntentTimer.stop();
        _collapseGraceTimer.stop();
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
        if (!Policy.isValidPage(pageId))
            return false;
        currentPage = pageId;
        rememberedPage = pageId;
        pin(screenName);
        return true;
    }

    function cycle(delta) {
        currentPage = Policy.cyclePage(currentPage, delta);
        rememberedPage = currentPage;
    }

    function activateCurrent() {
        const activation = Policy.activationForPage(currentPage);
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

    function handleEscape() {
        mode = Policy.escapeTarget(mode);
    }
}
