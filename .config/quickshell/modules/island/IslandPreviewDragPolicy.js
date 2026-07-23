.pragma library

// Lifecycle for island screenshot/recording "drag out".
// Never cancel Drag.active or destroy the source while QDrag::exec is running —
// that races Wayland data_source_send against a freed QMimeData (SIGSEGV).

function onHandlerActiveChanged(dragSession, qtDragStarted, active) {
    if (active)
        return { dragSession: true, qtDragStarted: false, action: "start" };
    if (qtDragStarted)
        return { dragSession: dragSession, qtDragStarted: true, action: "wait" };
    if (!dragSession)
        return { dragSession: false, qtDragStarted: false, action: "noop" };
    return { dragSession: false, qtDragStarted: false, action: "dismiss" };
}

function shouldStartQtDrag(dragSession, qtDragStarted, handlerStillActive) {
    if (!dragSession)
        return false;
    if (qtDragStarted)
        return false;
    return !!handlerStillActive;
}

function onDragFinished() {
    return { dragSession: false, qtDragStarted: false, action: "dismiss" };
}

function shouldCancelDragOnHandlerInactive() {
    return false;
}
