// node test_shell_edges.js — checks ShellEdges.js (a QML .pragma library).
// runInThisContext keeps results in this realm so deepStrictEqual can compare them.
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

vm.runInThisContext(fs.readFileSync(__dirname + "/ShellEdges.js", "utf8").replace(/^\.pragma library$/m, ""));
const E = globalThis;

// isVertical / opposite
assert.strictEqual(E.isVertical("left"), true);
assert.strictEqual(E.isVertical("top"), false);
assert.strictEqual(E.opposite("left"), "right");
assert.strictEqual(E.opposite("garbage"), "bottom");

// nearestEdge on a 1000x500 screen
assert.strictEqual(E.nearestEdge(500, 10, 1000, 500), "top");
assert.strictEqual(E.nearestEdge(500, 490, 1000, 500), "bottom");
assert.strictEqual(E.nearestEdge(20, 250, 1000, 500), "left");
assert.strictEqual(E.nearestEdge(990, 250, 1000, 500), "right");

// swapResult: bar and dock never share an edge
assert.deepStrictEqual(E.swapResult("top", "bottom", "bar", "left"), { bar: "left", dock: "bottom" });
assert.deepStrictEqual(E.swapResult("top", "bottom", "bar", "bottom"), { bar: "bottom", dock: "top" });
assert.deepStrictEqual(E.swapResult("top", "bottom", "dock", "top"), { bar: "bottom", dock: "top" });
assert.deepStrictEqual(E.swapResult("top", "bottom", "dock", "bottom"), { bar: "top", dock: "bottom" }); // dropped on own edge
assert.deepStrictEqual(E.swapResult("top", "bottom", "dock", "diagonal"), { bar: "top", dock: "bottom" });
assert.deepStrictEqual(E.swapResult("top", "bottom", "island", "left"), { bar: "top", dock: "bottom" });

// normalizePair: settings-file values
assert.deepStrictEqual(E.normalizePair("", ""), { bar: "top", dock: "bottom" });
assert.deepStrictEqual(E.normalizePair("left", "garbage"), { bar: "left", dock: "bottom" });
assert.deepStrictEqual(E.normalizePair("right", "right"), { bar: "right", dock: "left" });
assert.deepStrictEqual(E.normalizePair("garbage", "top"), { bar: "top", dock: "bottom" });

// edgeCoords / atActivationEdge — monitor at (100, 50), 1000x500, dock 200 long, slop 4
const g = { x: 100, y: 50, width: 1000, height: 500 };
assert.deepStrictEqual(E.edgeCoords("bottom", g, 600, 549), { along: 500, depth: 0, length: 1000 });
assert.deepStrictEqual(E.edgeCoords("top", g, 600, 52), { along: 500, depth: 2, length: 1000 });
assert.deepStrictEqual(E.edgeCoords("left", g, 100, 300), { along: 250, depth: 0, length: 500 });
assert.deepStrictEqual(E.edgeCoords("right", g, 1098, 300), { along: 250, depth: 1, length: 500 });
assert.strictEqual(E.atActivationEdge("bottom", g, 600, 549, 200, 4), true);
assert.strictEqual(E.atActivationEdge("bottom", g, 600, 540, 200, 4), false); // too far from the edge
assert.strictEqual(E.atActivationEdge("bottom", g, 150, 549, 200, 4), false); // outside the dock's span
assert.strictEqual(E.atActivationEdge("top", g, 600, 50, 200, 4), true);
assert.strictEqual(E.atActivationEdge("left", g, 101, 300, 200, 4), true);
assert.strictEqual(E.atActivationEdge("left", g, 101, 60, 200, 4), false);
assert.strictEqual(E.atActivationEdge("right", g, 1099, 300, 200, 4), true);
// A top bar reserving 40px pushes a left dock's centre down by 20px: span 166..374, not 146..354
assert.strictEqual(E.atActivationEdge("left", g, 101, 50 + 370, 200, 4, 40, 0), true);
assert.strictEqual(E.atActivationEdge("left", g, 101, 50 + 150, 200, 4, 40, 0), false);

// barInsets: how much of the dock's edge the bar reserves at the start/end of that edge
assert.deepStrictEqual(E.barInsets("left", "top", 28), { start: 28, end: 0 });
assert.deepStrictEqual(E.barInsets("right", "bottom", 28), { start: 0, end: 28 });
assert.deepStrictEqual(E.barInsets("bottom", "left", 36), { start: 36, end: 0 });
assert.deepStrictEqual(E.barInsets("top", "right", 36), { start: 0, end: 36 });
assert.deepStrictEqual(E.barInsets("bottom", "top", 28), { start: 0, end: 0 }); // parallel: length untouched
assert.deepStrictEqual(E.barInsets("left", "right", 36), { start: 0, end: 0 });

// dockFrame: the dock's "down" (towards its edge) and "right" (icon order) per edge,
// and glyphFrame nested inside dockFrame leaves content upright.
const down = { bottom: [0, 1], top: [0, -1], left: [-1, 0], right: [1, 0] };
const order = { bottom: [1, 0], top: [1, 0], left: [0, 1], right: [0, 1] };
for (const edge of ["top", "bottom", "left", "right"]) {
    const f = E.dockFrame(edge);
    assert.deepStrictEqual(E.applyFrame(f, 0, 1), { x: down[edge][0], y: down[edge][1] }, edge + " down");
    assert.deepStrictEqual(E.applyFrame(f, 1, 0), { x: order[edge][0], y: order[edge][1] }, edge + " order");
    for (const [vx, vy] of [[1, 0], [0, 1]]) {
        const inner = E.applyFrame(E.glyphFrame(edge), vx, vy);
        assert.deepStrictEqual(E.applyFrame(f, inner.x, inner.y), { x: vx, y: vy }, edge + " upright");
    }
}

// surfaceOrigin: bar stretches along its edge (with gap), dock is centred on its edge
assert.deepStrictEqual(E.surfaceOrigin("top", true, 1000, 500, 1000, 30, 5), { x: 0, y: 5 });
assert.deepStrictEqual(E.surfaceOrigin("bottom", true, 1000, 500, 1000, 30, 5), { x: 0, y: 465 });
assert.deepStrictEqual(E.surfaceOrigin("right", true, 1000, 500, 40, 500, 0), { x: 960, y: 0 });
assert.deepStrictEqual(E.surfaceOrigin("left", false, 1000, 500, 190, 300, 0), { x: 0, y: 100 });
assert.deepStrictEqual(E.surfaceOrigin("bottom", false, 1000, 500, 300, 190, 0), { x: 350, y: 310 });

// edgeIsShared: a dock on an edge shared with another monitor gets a wider
// reveal strip (Nick's DP-5/DP-4 side-by-side setup).
const dp4 = { x: 5560, y: 0, width: 3440, height: 1440 };
const dp5 = { x: 3000, y: 0, width: 2560, height: 1440 };
assert.strictEqual(E.edgeIsShared("left", dp4, [dp5]), true);
assert.strictEqual(E.edgeIsShared("right", dp4, [dp5]), false);
assert.strictEqual(E.edgeIsShared("top", dp4, [dp5]), false);
assert.strictEqual(E.edgeIsShared("bottom", dp4, [dp5]), false);
const below = { x: 5560, y: 1440, width: 3440, height: 1440 };
assert.strictEqual(E.edgeIsShared("bottom", dp4, [below]), true);
const cornerOnly = { x: 9000, y: 1440, width: 1000, height: 1000 }; // touches only at a corner
assert.strictEqual(E.edgeIsShared("right", dp4, [cornerOnly]), false);
assert.strictEqual(E.edgeIsShared("left", dp4, []), false);

// verticalLabel: glyph, plus a short value stacked underneath
assert.strictEqual(E.verticalLabel("󰏔 3"), "󰏔\n3");
assert.strictEqual(E.verticalLabel("󱄠 45%"), "󱄠\n45%");
assert.strictEqual(E.verticalLabel("󰤨 MyHomeWifi 70%"), "󰤨");
assert.strictEqual(E.verticalLabel("󰂚"), "󰂚");
assert.strictEqual(E.verticalLabel(""), "");

console.log("ok");
