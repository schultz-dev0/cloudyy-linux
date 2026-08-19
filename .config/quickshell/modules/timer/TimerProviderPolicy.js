.pragma library

function _isNonNegativeInteger(value) {
    return Number.isInteger(value) && value >= 0;
}

function _validRecord(timer) {
    if (!timer || typeof timer !== "object"
            || typeof timer.id !== "string" || timer.id.length === 0
            || typeof timer.label !== "string"
            || (timer.mode !== "countdown" && timer.mode !== "stopwatch")
            || (timer.state !== "running" && timer.state !== "paused"
                && timer.state !== "completed")
            || !_isNonNegativeInteger(timer.elapsed_seconds)
            || !_isNonNegativeInteger(timer.created_at)
            || !_isNonNegativeInteger(timer.transitioned_at))
        return false;

    if (timer.mode === "countdown") {
        return _isNonNegativeInteger(timer.duration_seconds) && timer.duration_seconds > 0
            && _isNonNegativeInteger(timer.remaining_seconds)
            && (timer.state === "running"
                ? _isNonNegativeInteger(timer.deadline_at)
                : timer.deadline_at === null);
    }
    return timer.duration_seconds === null && timer.remaining_seconds === null
        && timer.deadline_at === null && timer.state !== "completed";
}

function _normalize(timer, generatedAt) {
    return {
        timerId: timer.id,
        label: timer.label,
        mode: timer.mode,
        timerState: timer.state,
        targetSeconds: timer.duration_seconds === null ? 0 : timer.duration_seconds,
        elapsedSeconds: timer.elapsed_seconds,
        remainingSeconds: timer.remaining_seconds === null ? 0 : timer.remaining_seconds,
        createdAt: timer.created_at,
        transitionedAt: timer.transitioned_at,
        deadlineAt: timer.deadline_at === null ? 0 : timer.deadline_at,
        generatedAt: generatedAt
    };
}

function parseSnapshot(text, previousTimers) {
    let snapshot;
    try {
        snapshot = JSON.parse(text);
    } catch (error) {
        return { accepted: false, timers: previousTimers, completed: [], error: "Invalid timer provider JSON" };
    }
    if (!snapshot || typeof snapshot !== "object" || snapshot.version !== 1
            || !_isNonNegativeInteger(snapshot.generated_at) || !Array.isArray(snapshot.timers))
        return { accepted: false, timers: previousTimers, completed: [], error: "Invalid timer provider snapshot" };

    const timers = [];
    const completed = [];
    for (let i = 0; i < snapshot.timers.length; i++) {
        const timer = snapshot.timers[i];
        if (!_validRecord(timer))
            return { accepted: false, timers: previousTimers, completed: [], error: "Invalid timer provider record" };
        const normalized = _normalize(timer, snapshot.generated_at);
        if (timer.state === "completed")
            completed.push(normalized);
        else
            timers.push(normalized);
    }
    return { accepted: true, timers: timers, completed: completed, error: "" };
}

function nearestCountdown(timers) {
    let nearest = null;
    for (let i = timers.length - 1; i >= 0; i--) {
        const timer = timers[i];
        if (timer.mode === "countdown" && timer.timerState === "running"
                && (!nearest || timer.remainingSeconds < nearest.remainingSeconds))
            nearest = timer;
    }
    return nearest;
}

function primaryTimer(timers) {
    const countdown = nearestCountdown(timers);
    if (countdown)
        return countdown;
    for (let i = timers.length - 1; i >= 0; i--) {
        if (timers[i].mode === "stopwatch" && timers[i].timerState === "running")
            return timers[i];
    }
    return null;
}

function pageTimer(timers) {
    const primary = primaryTimer(timers);
    if (primary)
        return primary;
    for (let i = timers.length - 1; i >= 0; i--) {
        if (timers[i].timerState === "paused")
            return timers[i];
    }
    return null;
}

function displaySeconds(timer, presentationEpoch) {
    const delta = timer.timerState === "running"
        ? Math.max(0, presentationEpoch - timer.generatedAt) : 0;
    if (timer.mode === "countdown")
        return Math.max(0, timer.remainingSeconds - delta);
    return timer.elapsedSeconds + delta;
}

function shouldRecoverCompactFocus(compactActive, displayTimerId, removedTimerId,
        focusedAction, recoveryPending) {
    return compactActive && displayTimerId === removedTimerId
        && (focusedAction === "pause" || focusedAction === "reset"
            || focusedAction === "stop") && !recoveryPending;
}
