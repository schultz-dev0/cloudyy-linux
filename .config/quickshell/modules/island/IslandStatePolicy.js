.pragma library
.import "IslandRegistryPolicy.js" as RegistryPolicy

function cyclePage(id, delta, availableIds) {
    return RegistryPolicy.cyclePage(id, delta, availableIds);
}

function repairNavigation(currentId, rememberedId, orderedIds, availableIds) {
    const remembered = rememberedId || currentId;
    if (availableIds.length === 0) {
        return {
            currentPage: "",
            rememberedPage: remembered
        };
    }
    if (availableIds.indexOf(remembered) !== -1) {
        return {
            currentPage: remembered,
            rememberedPage: remembered
        };
    }
    return {
        currentPage: RegistryPolicy.repairCurrentPage(
            currentId, orderedIds, availableIds),
        rememberedPage: remembered
    };
}

function activationForPage(integration) {
    return integration?.activation ?? "stayCompact";
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
