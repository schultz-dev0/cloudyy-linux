.pragma library

const knownIds = ["notifications", "timer", "media", "agents"];

function defaultSettings() {
    return {
        version: 1,
        order: knownIds.slice(),
        enabled: {
            notifications: true,
            timer: true,
            media: true,
            agents: true
        }
    };
}

function validSettings(value) {
    if (value === null || typeof value !== "object" || Array.isArray(value)
            || value.version !== 1 || !Array.isArray(value.order)
            || value.enabled === null || typeof value.enabled !== "object"
            || Array.isArray(value.enabled))
        return false;
    for (let i = 0; i < value.order.length; i++) {
        if (typeof value.order[i] !== "string")
            return false;
    }
    const enabledKeys = Object.keys(value.enabled);
    for (let i = 0; i < enabledKeys.length; i++) {
        if (typeof value.enabled[enabledKeys[i]] !== "boolean")
            return false;
    }
    return true;
}

function normalizeSettings(value, lastValid) {
    if (!validSettings(value))
        value = validSettings(lastValid) ? lastValid : defaultSettings();

    const order = [];
    for (let i = 0; i < value.order.length; i++) {
        const id = value.order[i];
        if (knownIds.indexOf(id) !== -1 && order.indexOf(id) === -1)
            order.push(id);
    }
    for (let i = 0; i < knownIds.length; i++) {
        if (order.indexOf(knownIds[i]) === -1)
            order.push(knownIds[i]);
    }

    const enabled = {};
    for (let i = 0; i < knownIds.length; i++) {
        const id = knownIds[i];
        enabled[id] = Object.prototype.hasOwnProperty.call(value.enabled, id)
            ? value.enabled[id] : true;
    }
    return { version: 1, order: order, enabled: enabled };
}

function availablePageIds(settings, integrations) {
    const normalized = normalizeSettings(settings);
    const integrationsById = {};
    for (let i = 0; i < integrations.length; i++)
        integrationsById[integrations[i].id] = integrations[i];
    // hasData is deliberately NOT part of this check — it only controls
    // whether an integration contributes a resting-pill summary
    // (highestRestingSummary). Gating navigability on hasData made pages
    // like Agents unreachable whenever they were empty, even though their
    // own content is how you see the empty state — a self-locking dead end.
    // pageComponent IS required — an integration with no page (Timer, which
    // is resting-pill-only now) must never be cyclable/pinnable.
    return normalized.order.filter(function(id) {
        const integration = integrationsById[id];
        return normalized.enabled[id] && integration
            && integration.detected === true && !!integration.pageComponent;
    });
}

function repairCurrentPage(currentId, orderedIds, availableIds) {
    if (availableIds.length === 0)
        return "";
    if (availableIds.indexOf(currentId) !== -1)
        return currentId;
    const currentIndex = orderedIds.indexOf(currentId);
    if (currentIndex === -1)
        return availableIds[0];
    for (let distance = 1; distance < orderedIds.length; distance++) {
        const right = currentIndex + distance;
        if (right < orderedIds.length && availableIds.indexOf(orderedIds[right]) !== -1)
            return orderedIds[right];
        const left = currentIndex - distance;
        if (left >= 0 && availableIds.indexOf(orderedIds[left]) !== -1)
            return orderedIds[left];
    }
    return availableIds[0];
}

function cyclePage(currentId, delta, availableIds) {
    if (availableIds.length === 0)
        return "";
    const currentIndex = availableIds.indexOf(currentId);
    if (currentIndex === -1)
        return availableIds[0];
    const next = ((currentIndex + delta) % availableIds.length + availableIds.length)
        % availableIds.length;
    return availableIds[next];
}

function highestRestingSummary(summaries) {
    let recording = null;
    let countdown = null;
    let media = null;
    let agent = null;
    let notification = null;
    for (let i = 0; i < summaries.length; i++) {
        const summary = summaries[i];
        if (!summary)
            continue;
        if (summary.kind === "recording" && summary.active === true)
            recording = recording || summary;
        else if (summary.kind === "countdown" && summary.active === true
                && Number.isFinite(summary.remainingSeconds)
                && (!countdown || summary.remainingSeconds < countdown.remainingSeconds))
            countdown = summary;
        else if (summary.kind === "media" && summary.playing === true)
            media = media || summary;
        else if (summary.kind === "agent" && summary.live === true
                && Number.isFinite(summary.startedAt)
                && (!agent || summary.startedAt < agent.startedAt))
            agent = summary;
        else if (summary.kind === "notification" && summary.unreadCount > 0)
            notification = notification || summary;
    }
    return recording || countdown || media || agent || notification;
}
