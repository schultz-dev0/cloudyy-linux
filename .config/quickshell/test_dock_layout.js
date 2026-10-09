// node test_dock_layout.js — checks modules/dock/DockLayout.js (a QML .pragma library).
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

vm.runInThisContext(fs.readFileSync(__dirname + "/modules/dock/DockLayout.js", "utf8").replace(/^\.pragma library$/m, ""));
const L = globalThis;

// shortName: lower-case, cut to cap INCLUDING the ellipsis, cap 0 = no cut
assert.strictEqual(L.shortName("Obsidian", 6), "obsid…");
assert.strictEqual(L.shortName("zen", 6), "zen");
assert.strictEqual(L.shortName("Kitty", 5), "kitty");
assert.strictEqual(L.shortName("abcdefg", 6), "abcde…");
assert.strictEqual(L.shortName("cloudyy-linux", 10), "cloudyy-l…");
assert.strictEqual(L.shortName("cloudyy-linux", 0), "cloudyy-linux");
assert.strictEqual(L.shortName("ab", 1), "…");
assert.strictEqual(L.shortName("", 6), "");
assert.strictEqual(L.shortName(null, 6), "");
assert.strictEqual(L.shortName(undefined, 0), "");

// ledCount: none when closed, 1..3 when open
assert.strictEqual(L.ledCount(0, false), 0);
assert.strictEqual(L.ledCount(5, false), 0);
assert.strictEqual(L.ledCount(1, true), 1);
assert.strictEqual(L.ledCount(2, true), 2);
assert.strictEqual(L.ledCount(7, true), 3);
assert.strictEqual(L.ledCount(0, true), 1);
assert.strictEqual(L.ledCount(undefined, true), 1);

// widths with charW = 7 (integers keep the sums readable)
assert.strictEqual(L.ledsWidth(0), 0);
assert.strictEqual(L.ledsWidth(2), 12);
assert.strictEqual(L.ledsWidth(3), 19);
assert.strictEqual(L.segmentWidth("zen", 2, 7), 94);
assert.strictEqual(L.segmentWidth("steam", 0, 7), 88);

// railLength: rim + segments (horizontal), rim + rows (vertical), empty is just the rim
const full = [{ name: "obsidian", leds: 1 }, { name: "zen", leds: 2 }];
assert.strictEqual(L.railLength([{ name: "zen", leds: 2 }, { name: "steam", leds: 0 }], 0, 7, false), 184);
assert.strictEqual(L.railLength(full, 0, 7, false), 218);
assert.strictEqual(L.railLength(full, 6, 7, false), 204);
assert.strictEqual(L.railLength(full, 0, 7, true), 70);
assert.strictEqual(L.railLength([], 0, 7, false), 2);
assert.strictEqual(L.railLength([], 0, 7, true), 2);

// sideThickness: widest side row = padding + icon + gap + 10 chars + gap + 3 LEDs, plus rim (review focus 2)
assert.strictEqual(L.sideThickness(7), 155);
assert.strictEqual(L.sideThickness(7) - L.RIM, 2 * L.PAD_V + L.ICON_V + L.GAP_V + 10 * 7 + L.GAP_V + L.ledsWidth(3));

// pickNameCap: 0 while the full-name rail fits, 6 the moment it overflows
assert.strictEqual(L.pickNameCap(full, 218, 7), 0);
assert.strictEqual(L.pickNameCap(full, 217, 7), 6);
assert.strictEqual(L.pickNameCap([], 0, 7), 0);
// screen size not known yet (0 or negative): never truncate on a guess
assert.strictEqual(L.pickNameCap(full, 0, 7), 0);
assert.strictEqual(L.pickNameCap(full, -24, 7), 0);
assert.strictEqual(L.pickNameCap([], 2, 7), 0);

console.log("ok");
