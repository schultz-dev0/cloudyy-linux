import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/timer/TimerProviderPolicy.js" as Policy

TestCase {
    name: "TimerProviderPolicy"

    readonly property var validSnapshot: ({
        version: 1,
        generated_at: 200,
        timers: [
            {
                id: "paused",
                label: "Paused",
                mode: "stopwatch",
                state: "paused",
                duration_seconds: null,
                elapsed_seconds: 30,
                remaining_seconds: null,
                created_at: 100,
                transitioned_at: 150,
                deadline_at: null
            },
            {
                id: "later",
                label: "Later countdown",
                mode: "countdown",
                state: "running",
                duration_seconds: 300,
                elapsed_seconds: 200,
                remaining_seconds: 100,
                created_at: 110,
                transitioned_at: 120,
                deadline_at: 300
            },
            {
                id: "nearer",
                label: "Nearer countdown",
                mode: "countdown",
                state: "running",
                duration_seconds: 60,
                elapsed_seconds: 40,
                remaining_seconds: 20,
                created_at: 120,
                transitioned_at: 180,
                deadline_at: 220
            },
            {
                id: "stopwatch",
                label: "Running stopwatch",
                mode: "stopwatch",
                state: "running",
                duration_seconds: null,
                elapsed_seconds: 10,
                remaining_seconds: null,
                created_at: 130,
                transitioned_at: 190,
                deadline_at: null
            }
        ]
    })

    function test_valid_snapshot_is_normalized() {
        const result = Policy.parseSnapshot(JSON.stringify(validSnapshot), []);
        compare(result.accepted, true);
        compare(result.error, "");
        compare(result.timers.length, 4);
        compare(result.timers[2].timerId, "nearer");
        compare(result.timers[2].targetSeconds, 60);
        compare(result.timers[2].elapsedSeconds, 40);
        compare(result.timers[2].deadlineAt, 220);
        compare(result.timers[2].generatedAt, 200);
    }

    function test_invalid_json_retains_last_valid_timers() {
        const previous = [{ timerId: "kept" }];
        const malformed = Policy.parseSnapshot("not json", previous);
        compare(malformed.accepted, false);
        compare(malformed.timers, previous);
        verify(malformed.error.length > 0);

        const invalidRecord = JSON.parse(JSON.stringify(validSnapshot));
        invalidRecord.timers[0].state = "mystery";
        const rejected = Policy.parseSnapshot(JSON.stringify(invalidRecord), previous);
        compare(rejected.accepted, false);
        compare(rejected.timers, previous);
    }

    function test_invalid_numeric_fields_retain_last_valid_timers() {
        const previous = [{ timerId: "kept" }];
        const invalidValues = [
            ["generated_at", -1],
            ["generated_at", 200.5],
            ["elapsed_seconds", -1],
            ["elapsed_seconds", 1.5],
            ["duration_seconds", -1],
            ["duration_seconds", 60.5],
            ["remaining_seconds", -1],
            ["remaining_seconds", 1.5],
            ["created_at", -1],
            ["created_at", 1.5],
            ["transitioned_at", -1],
            ["transitioned_at", 1.5],
            ["deadline_at", -1],
            ["deadline_at", 220.5]
        ];
        for (let i = 0; i < invalidValues.length; i++) {
            const snapshot = JSON.parse(JSON.stringify(validSnapshot));
            const field = invalidValues[i][0];
            if (field === "generated_at")
                snapshot.generated_at = invalidValues[i][1];
            else
                snapshot.timers[2][field] = invalidValues[i][1];
            const result = Policy.parseSnapshot(JSON.stringify(snapshot), previous);
            compare(result.accepted, false, field + " accepted " + invalidValues[i][1]);
            compare(result.timers, previous, field + " did not retain prior timers");
        }
    }

    function test_deadline_semantics_retain_last_valid_timers() {
        const previous = [{ timerId: "kept" }];
        const runningWithoutDeadline = JSON.parse(JSON.stringify(validSnapshot));
        runningWithoutDeadline.timers[2].deadline_at = null;
        let result = Policy.parseSnapshot(JSON.stringify(runningWithoutDeadline), previous);
        compare(result.accepted, false);
        compare(result.timers, previous);

        const pausedWithDeadline = JSON.parse(JSON.stringify(validSnapshot));
        pausedWithDeadline.timers[1].state = "paused";
        result = Policy.parseSnapshot(JSON.stringify(pausedWithDeadline), previous);
        compare(result.accepted, false);
        compare(result.timers, previous);

        const stopwatchWithDeadline = JSON.parse(JSON.stringify(validSnapshot));
        stopwatchWithDeadline.timers[3].deadline_at = 220;
        result = Policy.parseSnapshot(JSON.stringify(stopwatchWithDeadline), previous);
        compare(result.accepted, false);
        compare(result.timers, previous);

        const completedWithNullDeadline = JSON.parse(JSON.stringify(validSnapshot));
        completedWithNullDeadline.timers[1].state = "completed";
        completedWithNullDeadline.timers[1].remaining_seconds = 0;
        completedWithNullDeadline.timers[1].deadline_at = null;
        result = Policy.parseSnapshot(JSON.stringify(completedWithNullDeadline), previous);
        compare(result.accepted, true);
        compare(result.completed.length, 1);
    }

    function test_expanded_card_display_values_are_finite_and_correct() {
        const timers = Policy.parseSnapshot(JSON.stringify(validSnapshot), []).timers;
        compare(Policy.displaySeconds(timers[2], 205), 15);
        compare(Policy.displaySeconds(timers[3], 205), 15);
        verify(Number.isFinite(Policy.displaySeconds(timers[2], 205)));
        verify(Number.isFinite(Policy.displaySeconds(timers[3], 205)));
    }

    function test_compact_structural_replacement_recovers_each_action_focus() {
        compare(Policy.shouldRecoverCompactFocus(false, "nearer", "nearer", "pause", false), false);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "other", "pause", false), false);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "nearer", "", false), false);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "nearer", "pause", false), true);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "nearer", "reset", false), true);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "nearer", "stop", false), true);
        compare(Policy.shouldRecoverCompactFocus(true, "nearer", "nearer", "pause", true), false);
    }

    function test_nearest_running_countdown_wins_primary_selection() {
        const timers = Policy.parseSnapshot(JSON.stringify(validSnapshot), []).timers;
        compare(Policy.nearestCountdown(timers).timerId, "nearer");
        compare(Policy.primaryTimer(timers).timerId, "nearer");
    }

    function test_page_falls_back_from_countdown_to_stopwatch_to_paused() {
        const timers = Policy.parseSnapshot(JSON.stringify(validSnapshot), []).timers;
        compare(Policy.pageTimer(timers).timerId, "nearer");
        compare(Policy.pageTimer([timers[0], timers[3]]).timerId, "stopwatch");
        compare(Policy.pageTimer([timers[0]]).timerId, "paused");
        compare(Policy.pageTimer([]), null);
    }
}
