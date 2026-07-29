.pragma library

function show(state) {
    return state === "active" ? "scene" : state;
}

function dismiss(state) {
    return state === "scene" ? "active" : state;
}
