import QtQuick
import Quickshell
import "modules/island" as QuickIsland

ShellRoot {
    id: root

    property int failures: 0
    property int activationFailedCount: 0
    property string activationFailedTarget: ""
    property int controlCenterRequestedCount: 0
    property int systemOverviewRequestedCount: 0

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
        function onSystemOverviewRequested() {
            root.systemOverviewRequestedCount++;
        }
    }

    Component.onCompleted: {
        QuickIsland.IslandState.hide();
        QuickIsland.IslandState.currentPage = "notifications";
        QuickIsland.IslandState.rememberedPage = "notifications";

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

        root.check(QuickIsland.IslandState.showPage("system", "DP-2"), true,
                   "system page accepted");
        QuickIsland.IslandState.activateCurrent();
        root.check(root.systemOverviewRequestedCount, 1, "system overview request count");
        root.check(QuickIsland.IslandState.mode, "pinned", "system overview request mode");
        QuickIsland.IslandState.completeExternalActivation("systemOverview", true);
        root.check(QuickIsland.IslandState.mode, "resting", "system overview success mode");
        root.check(QuickIsland.IslandState.openingScreenName, "",
                   "system overview success screen");
        root.check(root.activationFailedCount, 1, "success does not emit failure");

        if (root.failures === 0)
            console.info("TASK10_ISLAND_STATE_PASS");
        Qt.callLater(Qt.quit);
    }
}
