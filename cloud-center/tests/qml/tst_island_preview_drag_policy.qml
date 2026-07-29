import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/island/IslandPreviewDragPolicy.js" as Policy

TestCase {
    name: "IslandPreviewDragPolicy"

    function test_handler_active_starts_session() {
        const next = Policy.onHandlerActiveChanged(false, false, true);
        compare(next.action, "start");
        compare(next.dragSession, true);
        compare(next.qtDragStarted, false);
    }

    function test_handler_inactive_while_qt_drag_waits_for_finished() {
        const next = Policy.onHandlerActiveChanged(true, true, false);
        compare(next.action, "wait");
        verify(!Policy.shouldCancelDragOnHandlerInactive());
    }

    function test_handler_inactive_without_qt_drag_dismisses() {
        const next = Policy.onHandlerActiveChanged(true, false, false);
        compare(next.action, "dismiss");
        compare(next.dragSession, false);
    }

    function test_grab_ready_only_starts_while_gesture_still_active() {
        verify(Policy.shouldStartQtDrag(true, false, true));
        verify(!Policy.shouldStartQtDrag(true, false, false));
        verify(!Policy.shouldStartQtDrag(false, false, true));
        verify(!Policy.shouldStartQtDrag(true, true, true));
    }

    function test_drag_finished_dismisses() {
        const next = Policy.onDragFinished();
        compare(next.action, "dismiss");
        compare(next.dragSession, false);
        compare(next.qtDragStarted, false);
    }
}
