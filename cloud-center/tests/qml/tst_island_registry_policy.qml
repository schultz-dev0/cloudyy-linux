import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/island/IslandRegistryPolicy.js" as Policy

TestCase {
    name: "IslandRegistryPolicy"

    readonly property var defaults: ({
        version: 1,
        order: ["notifications", "timer", "media", "agents"],
        enabled: ({ notifications: true, timer: true, media: true, agents: true })
    })

    function test_normalize_removes_unknown_duplicates_and_appends_missing_ids() {
        const result = Policy.normalizeSettings({
            version: 1,
            order: ["media", "future", "media", "notifications"],
            enabled: ({ notifications: false, timer: true, media: true, agents: false, future: false })
        });
        compare(result.order.join(","), "media,notifications,timer,agents");
        compare(JSON.stringify(result.enabled), JSON.stringify({
            notifications: false, timer: true, media: true, agents: false
        }));
    }

    function test_invalid_live_values_retain_last_valid() {
        const previous = {
            version: 1,
            order: ["agents", "media", "timer", "notifications"],
            enabled: ({ notifications: true, timer: false, media: true, agents: true })
        };
        const invalidValues = [
            null,
            [],
            { version: 2, order: [], enabled: {} },
            { version: true, order: [], enabled: {} },
            { version: 1, order: "media", enabled: {} },
            { version: 1, order: ["media", 7], enabled: {} },
            { version: 1, order: [], enabled: [] },
            { version: 1, order: [], enabled: ({ media: 1 }) },
            { version: 1, order: [], enabled: ({ media: "yes" }) }
        ];
        for (let i = 0; i < invalidValues.length; i++) {
            const result = Policy.normalizeSettings(invalidValues[i], previous);
            compare(JSON.stringify(result), JSON.stringify(previous));
            verify(result !== previous);
        }
    }

    function test_missing_enabled_values_default_and_all_disabled_is_valid() {
        compare(
            JSON.stringify(Policy.normalizeSettings({ version: 1, order: [], enabled: {} })),
            JSON.stringify(defaults)
        );
        const result = Policy.normalizeSettings({
            version: 1,
            order: ["agents"],
            enabled: ({ notifications: false, timer: false, media: false, agents: false })
        });
        compare(result.order.join(","), "agents,notifications,timer,media");
        verify(!result.enabled.notifications && !result.enabled.timer
               && !result.enabled.media && !result.enabled.agents);
    }

    function test_integration_selection() {
        const settings = Policy.normalizeSettings({
            version: 1,
            order: ["agents", "media", "notifications", "timer"],
            enabled: ({ notifications: true, timer: true, media: true, agents: true })
        });
        const integrations = [
            { id: "notifications", detected: true, hasData: true, pageComponent: true },
            { id: "timer", detected: false, hasData: true, pageComponent: null },
            { id: "media", detected: true, hasData: false, pageComponent: true },
            { id: "agents", detected: true, hasData: true, pageComponent: true },
            { id: "future", detected: true, hasData: true, pageComponent: true }
        ];
        // timer is excluded by detected: false (and separately by
        // pageComponent: null — see test_pageless_integrations_are_never_
        // available for that case in isolation). media stays available
        // despite hasData: false — hasData no longer gates navigability,
        // only the resting-pill summary. A page with an empty state and its
        // own "create new" affordance (e.g. Agents' empty state) must still
        // be reachable when empty, or it can never get its first data.
        compare(Policy.availablePageIds(settings, integrations).join(","), "agents,media,notifications");
        compare(Policy.availablePageIds({
            version: 1,
            order: defaults.order,
            enabled: ({ notifications: false, timer: false, media: false, agents: false })
        }, integrations).length, 0);
    }

    function test_pageless_integrations_are_never_available() {
        // Timer's actual shape: fully detected, has data, enabled in
        // settings — but pageComponent: null (no island page anymore, see
        // IslandIntegrationRegistryModel.qml). Must still never appear in
        // availablePageIds; it only ever surfaces via the resting pill.
        const settings = Policy.normalizeSettings({
            version: 1,
            order: ["timer", "notifications"],
            enabled: ({ notifications: true, timer: true, media: true, agents: true })
        });
        const integrations = [
            { id: "timer", detected: true, hasData: true, pageComponent: null },
            { id: "notifications", detected: true, hasData: true, pageComponent: true }
        ];
        compare(Policy.availablePageIds(settings, integrations).join(","), "notifications");
    }

    function test_repair_uses_nearest_page_with_right_first_tie_break() {
        const ordered = ["notifications", "timer", "media", "agents"];
        compare(Policy.repairCurrentPage("timer", ordered, ["notifications", "media"]), "media");
        compare(Policy.repairCurrentPage("agents", ordered, ["notifications", "media"]), "media");
        compare(Policy.repairCurrentPage("media", ordered, ["notifications", "media"]), "media");
        compare(Policy.repairCurrentPage("unknown", ordered, ["media", "agents"]), "media");
        compare(Policy.repairCurrentPage("timer", ordered, []), "");
    }

    function test_cycle_handles_empty_single_and_wrapping_pages() {
        compare(Policy.cyclePage("notifications", 1, []), "");
        compare(Policy.cyclePage("unknown", 1, ["media"]), "media");
        compare(Policy.cyclePage("notifications", -1, ["notifications", "media", "agents"]), "agents");
        compare(Policy.cyclePage("agents", 1, ["notifications", "media", "agents"]), "notifications");
    }

    function test_resting_summary_uses_fixed_priority_not_input_order() {
        const summaries = [
            { kind: "notification", text: "Unread", unreadCount: 2 },
            { kind: "agent", text: "Claude", live: true, startedAt: 100 },
            null,
            { kind: "media", text: "Song", playing: true },
            { kind: "countdown", text: "0:20", active: true, remainingSeconds: 20 },
            { kind: "recording", text: "Recording", active: true }
        ];
        compare(Policy.highestRestingSummary(summaries).kind, "recording");
        compare(Policy.highestRestingSummary(summaries.slice(0, 5)).kind, "countdown");
        compare(Policy.highestRestingSummary([summaries[0], summaries[1]]).kind, "agent");
        compare(Policy.highestRestingSummary([null]), null);
    }

    function test_nearest_active_countdown_is_input_order_independent() {
        const farther = {
            kind: "countdown", text: "Farther", active: true, remainingSeconds: 80
        };
        const nearest = {
            kind: "countdown", text: "Nearest", active: true, remainingSeconds: 15
        };
        const inactive = {
            kind: "countdown", text: "Inactive", active: false, remainingSeconds: 1
        };
        compare(Policy.highestRestingSummary([farther, inactive, nearest]), nearest);
        compare(Policy.highestRestingSummary([nearest, farther]), nearest);
    }

    function test_only_playing_media_is_selected() {
        const paused = { kind: "media", text: "Paused", playing: false };
        const playing = { kind: "media", text: "Playing", playing: true };
        compare(Policy.highestRestingSummary([paused, playing]), playing);
        compare(Policy.highestRestingSummary([paused]), null);
    }

    function test_oldest_live_agent_session_is_selected() {
        const newer = { kind: "agent", text: "Newer", live: true, startedAt: 200 };
        const oldest = { kind: "agent", text: "Oldest", live: true, startedAt: 100 };
        const ended = { kind: "agent", text: "Ended", live: false, startedAt: 50 };
        compare(Policy.highestRestingSummary([newer, ended, oldest]), oldest);
        compare(Policy.highestRestingSummary([oldest, newer]), oldest);
    }

    function test_only_unread_notifications_are_selected() {
        const read = { kind: "notification", text: "Read", unreadCount: 0 };
        const unread = { kind: "notification", text: "Unread", unreadCount: 3 };
        compare(Policy.highestRestingSummary([read, unread]), unread);
        compare(Policy.highestRestingSummary([read]), null);
    }

    function test_inactive_recording_does_not_override_active_summary() {
        const inactive = { kind: "recording", text: "Stopped", active: false };
        const countdown = {
            kind: "countdown", text: "Countdown", active: true, remainingSeconds: 20
        };
        compare(Policy.highestRestingSummary([inactive, countdown]), countdown);
        compare(Policy.highestRestingSummary([inactive]), null);
    }
}
