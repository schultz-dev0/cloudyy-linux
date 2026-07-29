import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/idle/IdleState.js" as IdleState

TestCase {
    name: "IdleState"

    function test_show_only_enters_scene_from_active() {
        compare(IdleState.show("active"), "scene");
        compare(IdleState.show("scene"), "scene");
        compare(IdleState.show("locking"), "locking");
        compare(IdleState.show("locked"), "locked");
    }

    function test_duplicate_show_preserves_scene() {
        compare(IdleState.show("scene"), "scene");
    }

    function test_scene_can_be_dismissed_before_lock() {
        compare(IdleState.dismiss("active"), "active");
        compare(IdleState.dismiss("scene"), "active");
    }

    function test_dismissal_is_ignored_for_unknown_states() {
        compare(IdleState.dismiss("active"), "active");
        compare(IdleState.dismiss("locking"), "locking");
        compare(IdleState.dismiss("locked"), "locked");
    }
}
