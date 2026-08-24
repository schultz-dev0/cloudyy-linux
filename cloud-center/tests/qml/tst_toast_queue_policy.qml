import QtQuick
import QtTest
import "../../../.config/quickshell/modules/toast/ToastQueuePolicy.js" as Policy

TestCase {
    name: "ToastQueuePolicy"

    function test_sortQueue_orders_by_priority_desc_then_serial_asc() {
        const queue = [
            { id: "a", serial: 0, priority: 10 },
            { id: "b", serial: 1, priority: 90 },
            { id: "c", serial: 2, priority: 90 }
        ];
        const sorted = Policy.sortQueue(queue);
        compare(sorted.map(a => a.id).join(","), "b,c,a");
        // original array untouched
        compare(queue.map(a => a.id).join(","), "a,b,c");
    }

    function test_findQueuedOsd_matches_activityType_and_kind() {
        const queue = [
            { data: { activityType: "notification" } },
            { id: "vol", data: { activityType: "osd", kind: "volume" } },
            { data: { activityType: "osd", kind: "brightness" } }
        ];
        compare(Policy.findQueuedOsd(queue, "volume").id, "vol");
        compare(Policy.findQueuedOsd(queue, "nightlight"), null);
    }

    function test_decidePush_presents_immediately_when_idle() {
        const result = Policy.decidePush(null, "", { priority: 10, data: { activityType: "notification" } });
        compare(result.action, "present");
        compare(result.bumpCurrent, false);
    }

    function test_decidePush_queues_second_notification_fifo() {
        const current = { priority: 10, data: { activityType: "notification" } };
        const result = Policy.decidePush(current, "", { priority: 10, data: { activityType: "notification" } });
        compare(result.action, "queue");
    }

    function test_decidePush_higher_priority_preempts_and_bumps_current() {
        const current = { priority: 10, data: { activityType: "notification" } };
        const result = Policy.decidePush(current, "", { priority: 90, data: { activityType: "osd", kind: "volume" } });
        compare(result.action, "present");
        compare(result.bumpCurrent, true);
    }

    function test_decidePush_equal_or_lower_priority_extends_current() {
        const current = { priority: 90, data: { activityType: "osd", kind: "volume" } };
        const result = Policy.decidePush(current, "", { priority: 10, data: { activityType: "notification" } });
        compare(result.action, "extend");
    }

    function test_decidePush_queues_while_current_is_finishing() {
        const current = { priority: 10, data: { activityType: "notification" } };
        const result = Policy.decidePush(current, "activity-3", { priority: 90, data: { activityType: "osd", kind: "volume" } });
        compare(result.action, "queue");
    }
}
