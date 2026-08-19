import QtQuick
import QtTest
import "../../../../.config/quickshell/modules/island/AgentsPolicy.js" as Policy

TestCase {
    name: "AgentsPolicy"

    readonly property double nowMs: Date.parse("2026-08-14T12:00:00Z")
    readonly property var claudeRecord: ({
        schemaVersion: 1,
        recordId: "claude",
        provider: { id: "anthropic", name: "Claude" },
        planLabel: "Pro",
        allowances: [
            { id: "five-hour", label: "5-hour window", usedPercent: 72,
                resetAt: "2026-08-14T13:30:00Z" },
            { id: "weekly", label: "Weekly", usedPercent: 35, resetAt: null }
        ],
        dataUpdatedAt: "2026-08-14T11:45:00Z",
        lastAttemptAt: "2026-08-14T11:45:00Z",
        status: { state: "ok", message: "" },
        stale: false
    })

    function usageText(records) {
        return JSON.stringify({ usage: records, sessions: [] });
    }

    function test_usage_freshness_marks_stale_and_omits_expired_records() {
        const stale = JSON.parse(JSON.stringify(claudeRecord));
        stale.recordId = "stale";
        stale.provider.id = "stale";
        stale.dataUpdatedAt = "2026-08-14T11:30:00Z";
        stale.lastAttemptAt = "2026-08-14T11:30:00Z";
        const expired = JSON.parse(JSON.stringify(claudeRecord));
        expired.recordId = "expired";
        expired.provider.id = "expired";
        expired.dataUpdatedAt = "2026-08-13T12:00:00Z";
        expired.lastAttemptAt = "2026-08-13T12:00:00Z";

        const result = Policy.parseUsageSnapshot(
            usageText([claudeRecord, stale, expired]), [], 2, 2, nowMs);

        compare(result.accepted, true);
        compare(result.records.length, 2);
        compare(result.records[0].stale, false);
        compare(result.records[1].stale, true);
    }

    function test_malformed_usage_retains_last_valid_without_raw_output() {
        const previous = [{ recordId: "kept" }];
        const malformed = Policy.parseUsageSnapshot(
            "Bearer private-token", previous, 3, 3, nowMs);
        compare(malformed.accepted, false);
        compare(malformed.records, previous);
        compare(Object.keys(malformed).sort().join(","), "accepted,records");

        const invalid = JSON.parse(JSON.stringify(claudeRecord));
        invalid.allowances[0].usedPercent = 101;
        const rejected = Policy.parseUsageSnapshot(
            usageText([invalid]), previous, 3, 3, nowMs);
        compare(rejected.accepted, false);
        compare(rejected.records, previous);

        const invalidStatus = JSON.parse(JSON.stringify(claudeRecord));
        invalidStatus.status.message = 42;
        const rejectedStatus = Policy.parseUsageSnapshot(
            usageText([invalidStatus]), previous, 3, 3, nowMs);
        compare(rejectedStatus.accepted, false);
        compare(rejectedStatus.records, previous);
    }

    function test_timezone_less_provider_timestamps_fail_closed() {
        const previousRecords = [{ recordId: "kept" }];
        const usage = JSON.parse(JSON.stringify(claudeRecord));
        usage.dataUpdatedAt = "2026-08-14T11:45:00";
        let result = Policy.parseUsageSnapshot(
            usageText([usage]), previousRecords, 3, 3, nowMs);
        compare(result.accepted, false);
        compare(result.records, previousRecords);

        const previousSessions = [{ pid: 99 }];
        const session = [{ agentId: "claude", agentName: "Claude", pid: 11,
            workingDirectory: "/work", projectName: "work",
            startedAt: "2026-08-14T10:00:00", state: "running" }];
        result = Policy.parseSessionsSnapshot(
            JSON.stringify(session), previousSessions, 3, 3);
        compare(result.accepted, false);
        compare(result.sessions, previousSessions);
    }

    function test_generation_guard_rejects_obsolete_usage_response() {
        const previous = [{ recordId: "newer" }];
        const result = Policy.parseUsageSnapshot(
            usageText([claudeRecord]), previous, 4, 5, nowMs);
        compare(result.accepted, false);
        compare(result.records, previous);
    }

    function test_selected_provider_repairs_to_first_useful_record() {
        const codex = JSON.parse(JSON.stringify(claudeRecord));
        codex.recordId = "codex";
        codex.provider.id = "openai";
        compare(Policy.repairSelectedProvider("claude", [claudeRecord, codex]), "claude");
        compare(Policy.repairSelectedProvider("missing", [claudeRecord, codex]), "claude");
        compare(Policy.repairSelectedProvider("claude", []), "");
    }

    function test_tightest_allowance_has_highest_usage() {
        compare(Policy.tightestAllowance(claudeRecord.allowances).id, "five-hour");
        compare(Policy.tightestAllowance([]), null);
    }

    function test_reset_formatting_uses_stable_relative_labels() {
        compare(Policy.formatReset(null, nowMs), "No reset time");
        compare(Policy.formatReset("2026-08-14T12:45:00Z", nowMs), "Resets in 45m");
        compare(Policy.formatReset("2026-08-14T13:30:00Z", nowMs), "Resets in 1h 30m");
        compare(Policy.formatReset("2026-08-14T11:59:00Z", nowMs), "Reset due");
    }

    function test_sessions_are_validated_sorted_and_generation_guarded() {
        const sessions = [
            { agentId: "codex", agentName: "Codex", pid: 22,
                workingDirectory: "/work/new", projectName: "new",
                startedAt: "2026-08-14T11:30:00+00:00", state: "running" },
            { agentId: "claude", agentName: "Claude", pid: 11,
                workingDirectory: "/work/old", projectName: "old",
                startedAt: "2026-08-14T10:00:00+00:00", state: "running" }
        ];
        const accepted = Policy.parseSessionsSnapshot(JSON.stringify(sessions), [], 7, 7);
        compare(accepted.accepted, true);
        compare(accepted.sessions[0].pid, 11);
        compare(Policy.oldestSession(accepted.sessions).pid, 11);

        const previous = [{ pid: 99 }];
        const old = Policy.parseSessionsSnapshot(JSON.stringify(sessions), previous, 7, 8);
        compare(old.accepted, false);
        compare(old.sessions, previous);
        const malformed = Policy.parseSessionsSnapshot("private output", previous, 8, 8);
        compare(malformed.accepted, false);
        compare(malformed.sessions, previous);
    }

    function test_sessions_only_state_is_data_without_a_provider() {
        const sessions = [{ agentId: "opencode", agentName: "OpenCode", pid: 42,
            workingDirectory: "/work/cloudyy", projectName: "cloudyy",
            startedAt: "2026-08-14T10:00:00+00:00", state: "running" }];
        compare(Policy.hasData([], sessions), true);
        compare(Policy.repairSelectedProvider("", []), "");
        compare(Policy.hasData([], []), false);
    }
}
