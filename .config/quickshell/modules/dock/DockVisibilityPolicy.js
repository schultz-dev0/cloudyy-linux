.pragma library

function occupancyTransition(previousEmpty, currentEmpty, interactionBlocked) {
    if (currentEmpty)
        return previousEmpty ? "none" : "cancel";
    if (!previousEmpty)
        return "none";
    return interactionBlocked ? "defer" : "schedule";
}

function shouldCommitOccupancyHide(currentEmpty, interactionBlocked, fullscreen) {
    return !currentEmpty && !interactionBlocked && !fullscreen;
}

function nextPending(current, action) {
    if (action === "schedule" || action === "defer")
        return true;
    if (action === "cancel")
        return false;
    return current;
}

function canRevealAfterForcedHide(requiresExit, pointerInside) {
    return !requiresExit || !pointerInside;
}
