import QtQuick
import Quickshell
import "modules/island" as QuickIsland

ShellRoot {
    id: root

    property int failures: 0
    property int activationFailedCount: 0
    property string activationFailedTarget: ""
    property int controlCenterRequestedCount: 0

    function check(actual, expected, label) {
        if (actual === expected)
            return;
        failures++;
        console.error(`TASK10_ISLAND_STATE_FAIL ${label}: expected ${expected}, got ${actual}`);
    }

    Connections {
        target: QuickIsland.IslandState
        function onActivationFailed(target) {
            root.activationFailedCount++;
            root.activationFailedTarget = target;
        }
        function onControlCenterRequested() {
            root.controlCenterRequestedCount++;
        }
    }

    function setAvailable(ids) {
        const integrations = [
            { id: "notifications", activation: "controlCenter", pageComponent: null },
            { id: "timer", activation: "expand", pageComponent: null },
            { id: "media", activation: "stayCompact", pageComponent: null },
            { id: "agents", activation: "expand", pageComponent: null }
        ];
        const pages = integrations.filter(integration => ids.indexOf(integration.id) !== -1);
        QuickIsland.IslandIntegrationRegistry.integrations = integrations;
        QuickIsland.IslandIntegrationRegistry.availablePageIds = ids.slice();
        QuickIsland.IslandIntegrationRegistry.availablePages = pages;
        QuickIsland.IslandIntegrationRegistry.revision++;
    }

    Component.onCompleted: {
        root.setAvailable([]);
        QuickIsland.IslandState.hide();
        QuickIsland.IslandState.currentPage = "";
        QuickIsland.IslandState.rememberedPage = "timer";
        root.check(QuickIsland.IslandState.show("DP-0"), false, "empty show rejected");
        root.check(QuickIsland.IslandState.pin("DP-0"), false, "empty pin rejected");
        root.check(QuickIsland.IslandState.cycle(1), false, "empty cycle rejected");
        root.check(QuickIsland.IslandState.showPage("timer", "DP-0"), false,
                   "empty page rejected");
        root.check(QuickIsland.IslandState.mode, "resting", "empty registry stays resting");

        root.setAvailable(["notifications", "timer", "media", "agents"]);

        root.check(QuickIsland.IslandState.showPage("notifications", "DP-1"), true,
                   "control center page accepted");
        QuickIsland.IslandState.activateCurrent();
        root.check(root.controlCenterRequestedCount, 1, "control center request count");
        root.check(QuickIsland.IslandState.mode, "pinned", "control center request mode");
        QuickIsland.IslandState.completeExternalActivation("controlCenter", false);
        root.check(QuickIsland.IslandState.mode, "pinned", "control center failure mode");
        root.check(QuickIsland.IslandState.openingScreenName, "DP-1",
                   "control center failure screen");
        root.check(root.activationFailedCount, 1, "activation failure count");
        root.check(root.activationFailedTarget, "controlCenter", "activation failure target");

        root.check(QuickIsland.IslandState.showPage("timer", "DP-2"), true,
                   "timer page accepted");
        root.check(QuickIsland.IslandState.openingScreenName, "DP-2",
                   "explicit page transfers screen while pinned");
        QuickIsland.IslandState.activateCurrent();
        root.check(QuickIsland.IslandState.mode, "expanded", "timer expands dynamically");
        QuickIsland.IslandState.handleEscape();
        root.check(QuickIsland.IslandState.mode, "pinned", "expanded escape pins");

        QuickIsland.IslandState.handleEscape();
        root.check(QuickIsland.IslandState.mode, "resting", "escape closes pinned mode");
        root.check(QuickIsland.IslandState.openingScreenName, "",
                   "escape clears screen owner");

        QuickIsland.IslandState.showPage("timer", "DP-3");
        root.setAvailable(["notifications", "media", "agents"]);
        root.check(QuickIsland.IslandState.currentPage, "media",
                   "removed open page repairs to right neighbor");
        root.check(QuickIsland.IslandState.rememberedPage, "timer",
                   "removed open page remains remembered");
        root.setAvailable(["notifications", "timer", "media", "agents"]);
        root.check(QuickIsland.IslandState.currentPage, "timer",
                   "remembered open page returns");

        const snapshot = {
            mode: "expanded",
            currentPage: "timer",
            rememberedPage: "timer",
            openingScreenName: "DP-4"
        };
        root.setAvailable(["notifications", "media", "agents"]);
        root.check(QuickIsland.IslandState.restorePersistentSnapshot(snapshot), true,
                   "nonempty transient snapshot restored");
        root.check(QuickIsland.IslandState.currentPage, "media",
                   "transient snapshot repairs right first");
        root.check(QuickIsland.IslandState.rememberedPage, "timer",
                   "transient snapshot remembers removed page");
        root.check(QuickIsland.IslandState.mode, "expanded",
                   "transient snapshot preserves mode");
        root.check(QuickIsland.IslandState.openingScreenName, "DP-4",
                   "transient snapshot preserves owner");

        root.setAvailable([]);
        root.check(QuickIsland.IslandState.restorePersistentSnapshot(snapshot), false,
                   "empty transient snapshot rejected");
        root.check(QuickIsland.IslandState.mode, "resting",
                   "empty transient snapshot cannot open carousel");
        root.check(QuickIsland.IslandState.currentPage, "",
                   "empty transient snapshot has no current page");
        root.check(QuickIsland.IslandState.rememberedPage, "timer",
                   "empty transient snapshot keeps removed preference");
        root.setAvailable(["notifications", "timer", "media", "agents"]);
        root.check(QuickIsland.IslandState.currentPage, "timer",
                   "remembered page returns after empty registry");

        if (root.failures === 0)
            console.info("TASK10_ISLAND_STATE_PASS");
        Qt.callLater(Qt.quit);
    }
}
