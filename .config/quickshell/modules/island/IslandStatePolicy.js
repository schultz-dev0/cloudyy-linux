.pragma library

const pageIds = ["notifications", "calendar", "timer", "media", "system"];

function isValidPage(id) {
    return pageIds.indexOf(id) !== -1;
}

function cyclePage(id, delta) {
    const current = Math.max(0, pageIds.indexOf(id));
    const next = ((current + delta) % pageIds.length + pageIds.length) % pageIds.length;
    return pageIds[next];
}

function activationForPage(id) {
    if (id === "notifications") return "controlCenter";
    if (id === "calendar" || id === "timer") return "expand";
    if (id === "system") return "systemOverview";
    return "stayCompact";
}

function escapeTarget(mode) {
    return mode === "expanded" ? "pinned" : "resting";
}

function restoreAfterTransient(mode) {
    const persistentModes = ["resting", "hover", "pinned", "expanded"];
    return persistentModes.indexOf(mode) !== -1 ? mode : "resting";
}

function transientPresentation(activityType, pinned) {
    return activityType === "notification" && pinned ? "inline" : "full";
}

function shouldReviveOsd(activityType, currentKind, nextKind, finishing) {
    return finishing && activityType === "osd" && currentKind === nextKind;
}
