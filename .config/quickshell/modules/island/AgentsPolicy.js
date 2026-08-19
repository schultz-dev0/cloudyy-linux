.pragma library

const staleAfterMs = 30 * 60 * 1000;
const omitAfterMs = 24 * 60 * 60 * 1000;
const maxClockSkewMs = 5 * 60 * 1000;

function _nonemptyString(value) {
    return typeof value === "string" && value.trim().length > 0;
}

function _timestamp(value) {
    if (!_nonemptyString(value) || !/(?:Z|[+-]\d{2}:\d{2})$/.test(value))
        return NaN;
    return Date.parse(value);
}

function _validAllowance(allowance) {
    return allowance && typeof allowance === "object" && !Array.isArray(allowance)
        && _nonemptyString(allowance.id) && _nonemptyString(allowance.label)
        && typeof allowance.usedPercent === "number"
        && Number.isFinite(allowance.usedPercent)
        && allowance.usedPercent >= 0 && allowance.usedPercent <= 100
        && (allowance.resetAt === null || Number.isFinite(_timestamp(allowance.resetAt)));
}

function _normalizeUsageRecord(record, nowMs) {
    if (!record || typeof record !== "object" || Array.isArray(record)
            || record.schemaVersion !== 1 || !_nonemptyString(record.recordId)
            || !record.provider || typeof record.provider !== "object"
            || Array.isArray(record.provider) || !_nonemptyString(record.provider.id)
            || !_nonemptyString(record.provider.name) || typeof record.planLabel !== "string"
            || !Array.isArray(record.allowances) || !_nonemptyString(record.dataUpdatedAt)
            || !_nonemptyString(record.lastAttemptAt) || !record.status
            || typeof record.status !== "object" || Array.isArray(record.status)
            || ["ok", "unavailable", "error"].indexOf(record.status.state) === -1
            || typeof record.status.message !== "string")
        return undefined;

    const updatedAt = _timestamp(record.dataUpdatedAt);
    const attemptedAt = _timestamp(record.lastAttemptAt);
    if (!Number.isFinite(updatedAt) || !Number.isFinite(attemptedAt)
            || updatedAt - nowMs > maxClockSkewMs || attemptedAt - nowMs > maxClockSkewMs)
        return undefined;
    for (let i = 0; i < record.allowances.length; i++) {
        if (!_validAllowance(record.allowances[i]))
            return undefined;
    }

    const age = nowMs - updatedAt;
    if (age >= omitAfterMs)
        return null;
    return {
        recordId: record.recordId,
        providerId: record.provider.id,
        providerName: record.provider.name,
        planLabel: record.planLabel,
        allowances: record.allowances.map(function(allowance) {
            return {
                id: allowance.id,
                label: allowance.label,
                usedPercent: allowance.usedPercent,
                resetAt: allowance.resetAt
            };
        }),
        dataUpdatedAt: record.dataUpdatedAt,
        lastAttemptAt: record.lastAttemptAt,
        statusState: record.status.state,
        stale: age >= staleAfterMs
    };
}

function parseUsageSnapshot(text, previousRecords, responseGeneration,
        currentGeneration, nowMs) {
    if (responseGeneration !== currentGeneration)
        return { accepted: false, records: previousRecords };
    let snapshot;
    try {
        snapshot = JSON.parse(text);
    } catch (error) {
        return { accepted: false, records: previousRecords };
    }
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)
            || !Array.isArray(snapshot.usage))
        return { accepted: false, records: previousRecords };

    const records = [];
    const recordIds = {};
    for (let i = 0; i < snapshot.usage.length; i++) {
        const record = _normalizeUsageRecord(snapshot.usage[i], nowMs);
        if (record === undefined)
            return { accepted: false, records: previousRecords };
        if (record === null)
            continue;
        if (recordIds[record.recordId])
            return { accepted: false, records: previousRecords };
        recordIds[record.recordId] = true;
        records.push(record);
    }
    return { accepted: true, records: records };
}

function _normalizeSession(session) {
    if (!session || typeof session !== "object" || Array.isArray(session)
            || !_nonemptyString(session.agentId) || !_nonemptyString(session.agentName)
            || !Number.isInteger(session.pid) || session.pid <= 0
            || typeof session.workingDirectory !== "string"
            || typeof session.projectName !== "string"
            || !Number.isFinite(_timestamp(session.startedAt))
            || session.state !== "running")
        return null;
    return {
        agentId: session.agentId,
        agentName: session.agentName,
        pid: session.pid,
        workingDirectory: session.workingDirectory,
        projectName: session.projectName,
        startedAt: session.startedAt,
        state: "running"
    };
}

function parseSessionsSnapshot(text, previousSessions, responseGeneration,
        currentGeneration) {
    if (responseGeneration !== currentGeneration)
        return { accepted: false, sessions: previousSessions };
    let snapshot;
    try {
        snapshot = JSON.parse(text);
    } catch (error) {
        return { accepted: false, sessions: previousSessions };
    }
    if (!Array.isArray(snapshot))
        return { accepted: false, sessions: previousSessions };

    const sessions = [];
    const identities = {};
    for (let i = 0; i < snapshot.length; i++) {
        const session = _normalizeSession(snapshot[i]);
        if (!session)
            return { accepted: false, sessions: previousSessions };
        const identity = session.agentId + "\n" + session.pid + "\n" + session.startedAt;
        if (identities[identity])
            return { accepted: false, sessions: previousSessions };
        identities[identity] = true;
        sessions.push(session);
    }
    sessions.sort(function(left, right) {
        const timeDifference = _timestamp(left.startedAt) - _timestamp(right.startedAt);
        return timeDifference !== 0 ? timeDifference : left.pid - right.pid;
    });
    return { accepted: true, sessions: sessions };
}

function repairSelectedProvider(selectedId, records) {
    for (let i = 0; i < records.length; i++) {
        if (records[i].recordId === selectedId)
            return selectedId;
    }
    return records.length > 0 ? records[0].recordId : "";
}

function tightestAllowance(allowances) {
    let tightest = null;
    for (let i = 0; i < allowances.length; i++) {
        if (!tightest || allowances[i].usedPercent > tightest.usedPercent)
            tightest = allowances[i];
    }
    return tightest;
}

function formatReset(resetAt, nowMs) {
    if (resetAt === null)
        return "No reset time";
    const remainingMinutes = Math.ceil((_timestamp(resetAt) - nowMs) / 60000);
    if (!Number.isFinite(remainingMinutes) || remainingMinutes <= 0)
        return "Reset due";
    const hours = Math.floor(remainingMinutes / 60);
    const minutes = remainingMinutes % 60;
    if (hours === 0)
        return "Resets in " + minutes + "m";
    return "Resets in " + hours + "h" + (minutes > 0 ? " " + minutes + "m" : "");
}

function formatElapsed(startedAt, nowMs) {
    const elapsedMinutes = Math.max(0, Math.floor((nowMs - _timestamp(startedAt)) / 60000));
    const hours = Math.floor(elapsedMinutes / 60);
    const minutes = elapsedMinutes % 60;
    return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
}

function oldestSession(sessions) {
    return sessions.length > 0 ? sessions[0] : null;
}

function hasData(records, sessions) {
    for (let i = 0; i < records.length; i++) {
        if (records[i].allowances.length > 0)
            return true;
    }
    return sessions.length > 0;
}
