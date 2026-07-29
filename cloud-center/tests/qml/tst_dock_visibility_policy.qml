import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/dock/DockVisibilityPolicy.js" as Policy
import "../../../../.config/quickshell/overview/services/ClientSnapshot.js" as ClientSnapshot
import "../../../../.config/quickshell/overview/services/HyprEventPolicy.js" as HyprEventPolicy

TestCase {
    name: "DockVisibilityPolicy"

    function test_first_window_schedules_hide_even_with_stationary_hover() {
        compare(Policy.occupancyTransition(true, false, false), "schedule");
    }

    function test_empty_again_cancels_hide() {
        compare(Policy.occupancyTransition(false, true, false), "cancel");
    }

    function test_drag_defers_first_window_hide() {
        compare(Policy.occupancyTransition(true, false, true), "defer");
    }

    function test_commit_guards() {
        verify(Policy.shouldCommitOccupancyHide(false, false, false));
        verify(!Policy.shouldCommitOccupancyHide(true, false, false));
        verify(!Policy.shouldCommitOccupancyHide(false, true, false));
        verify(!Policy.shouldCommitOccupancyHide(false, false, true));
    }

    function test_pending_reducer() {
        compare(Policy.nextPending(false, "schedule"), true);
        compare(Policy.nextPending(true, "cancel"), false);
        compare(Policy.nextPending(true, "defer"), true);
        compare(Policy.nextPending(true, "none"), true);
    }

    function test_forced_hide_requires_pointer_exit_before_reveal() {
        verify(!Policy.canRevealAfterForcedHide(true, true));
        verify(Policy.canRevealAfterForcedHide(true, false));
        verify(Policy.canRevealAfterForcedHide(false, true));
    }

    function test_client_snapshot_maps_match_window_list() {
        const clients = [
            { address: "0x1", workspace: { id: 4 } },
            { address: "0x2", workspace: { id: 4 } }
        ];
        const snapshot = ClientSnapshot.build(clients);
        compare(snapshot.windowList.length, 2);
        compare(snapshot.addresses, ["0x1", "0x2"]);
        compare(snapshot.windowsByWorkspace[4].length, 2);
        compare(snapshot.windowByAddress["0x2"].workspace.id, 4);
    }

    function test_client_snapshot_keeps_special_windows_out_of_workspace_map() {
        const snapshot = ClientSnapshot.build([
            { address: "0xs", workspace: { id: -98 } }
        ]);
        compare(snapshot.windowList.length, 1);
        verify(snapshot.windowsByWorkspace[-98] === undefined);
    }

    function test_snapshot_cache_resolves_each_key_once() {
        const cache = {};
        let calls = 0;
        const resolve = () => {
            calls++;
            return { id: "cursor" };
        };
        const first = ClientSnapshot.resolveCached(cache, "cursor", resolve);
        const second = ClientSnapshot.resolveCached(cache, "cursor", resolve);
        compare(calls, 1);
        compare(first, second);
    }

    function test_title_events_use_one_trailing_window_refresh() {
        for (const eventName of ["windowtitle", "windowtitlev2"]) {
            const plan = HyprEventPolicy.updatePlan(eventName);
            compare(plan.debounce, "title");
            compare(plan.windows, true);
            compare(plan.monitors, false);
            compare(plan.workspaces, false);
            compare(plan.activeWorkspace, false);
        }
        verify(HyprEventPolicy.titleDebounceMs() > 250);
    }
}
