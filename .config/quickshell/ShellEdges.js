.pragma library

// ShellEdges.js — pure edge math for moving the bar and dock between screen
// edges. No QML types in here so node can test it: `node test_shell_edges.js`.

const EDGES = ["top", "bottom", "left", "right"];

function isEdge(edge) {
    return EDGES.indexOf(edge) >= 0;
}

function isVertical(edge) {
    return edge === "left" || edge === "right";
}

function opposite(edge) {
    return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[edge] ?? "bottom";
}

// Screen edge closest to (x, y) on a w×h screen.
function nearestEdge(x, y, w, h) {
    const distance = { top: y, bottom: h - y, left: x, right: w - x };
    return EDGES.reduce((best, edge) => distance[edge] < distance[best] ? edge : best, "top");
}

// Bar and dock never share an edge: moving one onto the other's edge swaps them.
function swapResult(barEdge, dockEdge, which, edge) {
    if (!isEdge(edge) || (which !== "bar" && which !== "dock"))
        return { bar: barEdge, dock: dockEdge };
    if (which === "bar")
        return { bar: edge, dock: dockEdge === edge ? barEdge : dockEdge };
    return { bar: barEdge === edge ? dockEdge : barEdge, dock: edge };
}

// Settings-file values -> a valid pair. Missing/garbage falls back to the
// defaults; a hand-edited collision moves the dock to the bar's opposite edge.
function normalizePair(bar, dock) {
    const b = isEdge(bar) ? bar : "top";
    const d = isEdge(dock) ? dock : "bottom";
    return { bar: b, dock: d === b ? opposite(b) : d };
}

// Cursor position relative to a monitor edge: `along` runs along the edge from
// the monitor's start, `depth` is the distance from the edge's outermost pixel.
function edgeCoords(edge, g, cx, cy) {
    if (edge === "top")
        return { along: cx - g.x, depth: cy - g.y, length: g.width };
    if (edge === "left")
        return { along: cy - g.y, depth: cx - g.x, length: g.height };
    if (edge === "right")
        return { along: cy - g.y, depth: g.x + g.width - 1 - cx, length: g.height };
    return { along: cx - g.x, depth: g.y + g.height - 1 - cy, length: g.width };
}

// Dock reveal gate: cursor within `slop` px of the edge and inside the dock's
// span, 4px tolerance each side. The dock is centred in the part of the edge
// the bar leaves free (`insetStart`/`insetEnd`, see barInsets).
function atActivationEdge(edge, g, cx, cy, dockLength, slop, insetStart, insetEnd) {
    const c = edgeCoords(edge, g, cx, cy);
    const before = insetStart ?? 0;
    const start = before + (c.length - before - (insetEnd ?? 0) - dockLength) / 2;
    return c.depth <= slop && c.along >= start - 4 && c.along <= start + dockLength + 4;
}

// Space the bar reserves at the start/end of the dock's edge ("start" is the
// top of a side edge, the left of a top/bottom edge). A bar parallel to the
// dock doesn't shorten it.
function barInsets(dockEdge, barEdge, barReserved) {
    if (isVertical(dockEdge) === isVertical(barEdge))
        return { start: 0, end: 0 };
    const atStart = barEdge === "top" || barEdge === "left";
    return { start: atStart ? barReserved : 0, end: atStart ? 0 : barReserved };
}

// Transform that turns the bottom-laid-out dock onto `edge`, applied
// scale-then-rotate about the frame centre (Dock.qml nests the two: scale on
// the inner item, rotation on the outer). Mirrors keep icon order
// left->right / top->bottom and keep magnify and labels growing into the
// screen.
function dockFrame(edge) {
    if (edge === "top")
        return { xScale: 1, yScale: -1, rotation: 0 };
    if (edge === "left")
        return { xScale: 1, yScale: 1, rotation: 90 };
    if (edge === "right")
        return { xScale: -1, yScale: 1, rotation: -90 };
    return { xScale: 1, yScale: 1, rotation: 0 };
}

// True if another monitor's rectangle abuts this monitor's `edge` line and
// overlaps it (a positive-length shared border, not just a touching corner).
// A dock there gets a wider reveal strip — the pointer can't push against a
// shared edge, it crosses onto the neighbour monitor instead.
function edgeIsShared(edge, g, others) {
    return others.some(other => {
        const abuts = edge === "right" ? other.x === g.x + g.width
            : edge === "left" ? other.x + other.width === g.x
            : edge === "bottom" ? other.y === g.y + g.height
            : edge === "top" ? other.y + other.height === g.y
            : false;
        if (!abuts)
            return false;
        const overlap = isVertical(edge)
            ? Math.min(g.y + g.height, other.y + other.height) - Math.max(g.y, other.y)
            : Math.min(g.x + g.width, other.x + other.width) - Math.max(g.x, other.x);
        return overlap > 0;
    });
}

// Undoes dockFrame for content that must stay upright (icons, labels).
// top and right are their own inverse; left needs the opposite rotation.
function glyphFrame(edge) {
    return edge === "left" ? { xScale: 1, yScale: 1, rotation: -90 } : dockFrame(edge);
}

// A frame applied to a vector in screen coords (y down, positive rotation is
// clockwise). `+ 0` turns -0 into 0.
function applyFrame(f, x, y) {
    const sx = x * f.xScale;
    const sy = y * f.yScale;
    const r = f.rotation * Math.PI / 180;
    return {
        x: Math.round(sx * Math.cos(r) - sy * Math.sin(r)) + 0,
        y: Math.round(sx * Math.sin(r) + sy * Math.cos(r)) + 0
    };
}

// Top-left of a layer surface on its screen. `stretch`: anchored along the
// whole edge (bar); otherwise centred on the edge (dock). `gap` is the margin
// on the anchored edge.
function surfaceOrigin(edge, stretch, screenW, screenH, winW, winH, gap) {
    const cx = stretch ? 0 : (screenW - winW) / 2;
    const cy = stretch ? 0 : (screenH - winH) / 2;
    if (edge === "top")
        return { x: cx, y: gap };
    if (edge === "left")
        return { x: gap, y: cy };
    if (edge === "right")
        return { x: screenW - winW - gap, y: cy };
    return { x: cx, y: screenH - winH - gap };
}

// Bar pill text on a vertical bar: the glyph, plus a short value (count, 45%)
// stacked underneath. Longer values (SSIDs, titles) are dropped.
function verticalLabel(label) {
    const parts = `${label ?? ""}`.split(" ").filter(part => part.length > 0);
    if (parts.length === 0)
        return "";
    return parts.length > 1 && parts[1].length <= 4 ? parts[0] + "\n" + parts[1] : parts[0];
}
