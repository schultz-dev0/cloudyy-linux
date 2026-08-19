import QtQuick
import QtTest
import "../../../.config/quickshell/modules/island/IslandStatePolicy.js" as Policy

TestCase {
    name: "IslandStatePolicy"

    function test_dynamic_cycle_wraps_and_handles_empty_and_one_page() {
        compare(Policy.cyclePage("timer", -1, ["timer", "media", "agents"]), "agents");
        compare(Policy.cyclePage("agents", 1, ["timer", "media", "agents"]), "timer");
        compare(Policy.cyclePage("missing", 1, ["timer", "media"]), "timer");
        compare(Policy.cyclePage("timer", 1, ["timer"]), "timer");
        compare(Policy.cyclePage("timer", 1, []), "");
    }

    function test_missing_current_repairs_right_first_and_remembers_preference() {
        const repaired = Policy.repairNavigation(
            "timer", "timer",
            ["notifications", "timer", "media", "agents"],
            ["notifications", "media", "agents"]);
        compare(repaired.currentPage, "media");
        compare(repaired.rememberedPage, "timer");
    }

    function test_noncanonical_order_repairs_to_configured_right_neighbor() {
        const repaired = Policy.repairNavigation(
            "timer", "timer",
            ["media", "timer", "notifications", "agents"],
            ["media", "notifications", "agents"]);
        compare(repaired.currentPage, "notifications");
        compare(repaired.rememberedPage, "timer");
    }

    function test_remembered_page_returns_when_available_again() {
        const repaired = Policy.repairNavigation(
            "media", "timer",
            ["notifications", "timer", "media", "agents"],
            ["notifications", "timer", "media", "agents"]);
        compare(repaired.currentPage, "timer");
        compare(repaired.rememberedPage, "timer");
    }

    function test_empty_navigation_retains_removed_preference() {
        const repaired = Policy.repairNavigation(
            "media", "timer",
            ["notifications", "timer", "media", "agents"], []);
        compare(repaired.currentPage, "");
        compare(repaired.rememberedPage, "timer");
    }

    function test_activationKinds() {
        compare(Policy.activationForPage({ activation: "controlCenter" }), "controlCenter");
        compare(Policy.activationForPage({ activation: "expand" }), "expand");
        compare(Policy.activationForPage({ activation: "stayCompact" }), "stayCompact");
        compare(Policy.activationForPage(null), "stayCompact");
    }

    function test_escapeHierarchy() {
        compare(Policy.escapeTarget("expanded"), "pinned");
        compare(Policy.escapeTarget("pinned"), "resting");
        compare(Policy.escapeTarget("hover"), "resting");
    }

    function test_persistentModeSurvivesTransient() {
        compare(Policy.restoreAfterTransient("resting"), "resting");
        compare(Policy.restoreAfterTransient("hover"), "hover");
        compare(Policy.restoreAfterTransient("pinned"), "pinned");
        compare(Policy.restoreAfterTransient("expanded"), "expanded");
    }

    function test_transientPresentationFollowsPersistentMode() {
        compare(Policy.transientPresentation("notification", false), "full");
        compare(Policy.transientPresentation("notification", true), "inline");
        compare(Policy.transientPresentation("osd", true), "full");
        compare(Policy.transientPresentation("screenshot", true), "full");
    }

    function test_sameKindFinishingOsdIsRevived() {
        verify(Policy.shouldReviveOsd("osd", "volume", "volume", true));
        verify(!Policy.shouldReviveOsd("osd", "volume", "brightness", true));
        verify(!Policy.shouldReviveOsd("osd", "volume", "volume", false));
        verify(!Policy.shouldReviveOsd("notification", "volume", "volume", true));
    }

}
