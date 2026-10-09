// node test_dock_keyboard.js — checks modules/dock/DockKeyboard.js (a QML .pragma library).
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");

vm.runInThisContext(fs.readFileSync(__dirname + "/modules/dock/DockKeyboard.js", "utf8").replace(/^\.pragma library$/m, ""));
const K = globalThis;

// Qt::Key values: Escape 0x1000000, Return 0x1000004, Enter 0x1000005,
// Left 0x1000012, Up 0x1000013, Right 0x1000014, Down 0x1000015, Space 0x20.
assert.strictEqual(K.actionForKey(0x01000000, ""), "close");
assert.strictEqual(K.actionForKey(0x01000004, "\r"), "new");
assert.strictEqual(K.actionForKey(0x01000005, "\r"), "new");
assert.strictEqual(K.actionForKey(0x20, " "), "jump");
assert.strictEqual(K.actionForKey(0x01000012, ""), "prev");
assert.strictEqual(K.actionForKey(0x01000013, ""), "prev");
assert.strictEqual(K.actionForKey(0x01000014, ""), "next");
assert.strictEqual(K.actionForKey(0x01000015, ""), "next");
assert.strictEqual(K.actionForKey(0x48, "h"), "prev");
assert.strictEqual(K.actionForKey(0x4b, "k"), "prev");
assert.strictEqual(K.actionForKey(0x4c, "l"), "next");
assert.strictEqual(K.actionForKey(0x4a, "j"), "next");
// Shift held (Super+Shift+D is still down) uppercases the text.
assert.strictEqual(K.actionForKey(0x48, "H"), "prev");
assert.strictEqual(K.actionForKey(0x41, "a"), "");
assert.strictEqual(K.actionForKey(0x41, undefined), "");

// clampIndex: list shrinks under the selection (review focus 2)
assert.strictEqual(K.clampIndex(5, 3), 2);
assert.strictEqual(K.clampIndex(-1, 3), 0);
assert.strictEqual(K.clampIndex(1, 3), 1);
assert.strictEqual(K.clampIndex(0, 0), -1);

// moveIndex clamps at both ends, no wrap
assert.strictEqual(K.moveIndex(0, 4, -1), 0);
assert.strictEqual(K.moveIndex(3, 4, 1), 3);
assert.strictEqual(K.moveIndex(1, 4, 1), 2);
assert.strictEqual(K.moveIndex(-1, 4, 1), 0);
assert.strictEqual(K.moveIndex(2, 0, 1), -1);

// cycleTarget: focused app's first window is the one you are already on, skip it (review focus 4)
assert.strictEqual(K.cycleTarget(2, true, 0), 1);
assert.strictEqual(K.cycleTarget(2, true, 1), 0);
assert.strictEqual(K.cycleTarget(3, true, 0), 1);
assert.strictEqual(K.cycleTarget(3, true, 1), 2);
assert.strictEqual(K.cycleTarget(3, true, 2), 0);
assert.strictEqual(K.cycleTarget(3, false, 0), 0);
assert.strictEqual(K.cycleTarget(3, false, 3), 0);
assert.strictEqual(K.cycleTarget(1, true, 0), 0);
assert.strictEqual(K.cycleTarget(0, true, 0), -1);

// shift + a movement key moves the pinned app instead of the selection
assert.strictEqual(K.actionForKey(0x48, "H", true), "moveprev");
assert.strictEqual(K.actionForKey(0x4b, "K", true), "moveprev");
assert.strictEqual(K.actionForKey(0x01000012, "", true), "moveprev");
assert.strictEqual(K.actionForKey(0x4c, "L", true), "movenext");
assert.strictEqual(K.actionForKey(0x4a, "J", true), "movenext");
assert.strictEqual(K.actionForKey(0x01000014, "", true), "movenext");
// plain keys and non-movement keys are unchanged (review focus 3)
assert.strictEqual(K.actionForKey(0x48, "h", false), "prev");
assert.strictEqual(K.actionForKey(0x4c, "l", undefined), "next");
assert.strictEqual(K.actionForKey(0x20, " ", true), "jump");
assert.strictEqual(K.actionForKey(0x01000004, "\r", true), "new");
assert.strictEqual(K.actionForKey(0x01000000, "", true), "close");
assert.strictEqual(K.actionForKey(0x41, "A", true), "");

console.log("ok");
