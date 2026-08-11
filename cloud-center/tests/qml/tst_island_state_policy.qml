import QtQuick
import QtTest
import "../../../.config/quickshell/modules/island/IslandStatePolicy.js" as Policy

TestCase {
    name: "IslandStatePolicy"

    function test_pageOrder() {
        compare(Policy.pageIds.join(","), "notifications,calendar,timer,media,system");
    }

    function test_cycleWraps() {
        compare(Policy.cyclePage("notifications", -1), "system");
        compare(Policy.cyclePage("system", 1), "notifications");
        compare(Policy.cyclePage("calendar", 2), "media");
    }

    function test_invalidPageFallsBack() {
        verify(!Policy.isValidPage("calculator"));
        compare(Policy.cyclePage("unknown", 0), "notifications");
    }

    function test_activationKinds() {
        compare(Policy.activationForPage("notifications"), "controlCenter");
        compare(Policy.activationForPage("calendar"), "expand");
        compare(Policy.activationForPage("timer"), "expand");
        compare(Policy.activationForPage("media"), "stayCompact");
        compare(Policy.activationForPage("system"), "systemOverview");
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
