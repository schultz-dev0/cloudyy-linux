.pragma library
// modules/dock/DockKeyboard.js — pure logic for the keyboard-summoned dock.
// Kept free of QML so test_dock_keyboard.js can run it under node.

// Qt::Key values (numeric: a .pragma library can't rely on the Qt.Key_* enums under node).
var KEY_ESCAPE = 0x01000000;
var KEY_RETURN = 0x01000004;
var KEY_ENTER = 0x01000005;
var KEY_LEFT = 0x01000012;
var KEY_UP = 0x01000013;
var KEY_RIGHT = 0x01000014;
var KEY_DOWN = 0x01000015;
var KEY_SPACE = 0x20;

function actionForKey(key, text, shift) {
    if (key === KEY_ESCAPE)
        return "close";
    if (key === KEY_RETURN || key === KEY_ENTER)
        return "new";
    if (key === KEY_SPACE)
        return "jump";
    var dir = "";
    if (key === KEY_LEFT || key === KEY_UP) {
        dir = "prev";
    } else if (key === KEY_RIGHT || key === KEY_DOWN) {
        dir = "next";
    } else {
        var t = ("" + (text || "")).toLowerCase();
        if (t === "h" || t === "k")
            dir = "prev";
        else if (t === "l" || t === "j")
            dir = "next";
    }
    if (dir === "")
        return "";
    // Shift = move the pinned app itself, not the selection.
    return shift ? "move" + dir : dir;
}

function clampIndex(index, count) {
    if (count <= 0)
        return -1;
    return Math.min(Math.max(index, 0), count - 1);
}

// No wrap: moving past either end stays on the end slot.
function moveIndex(index, count, delta) {
    return clampIndex(index + delta, count);
}

// Which window Space should focus on press number `step` (0-based) for an app
// with `count` windows. windowsForGroupKey() is MRU-ordered, so if the app is
// already focused its first window is the one you are on: start at the next one.
function cycleTarget(count, focusedIsFirst, step) {
    if (count <= 0)
        return -1;
    var start = (focusedIsFirst && count > 1) ? 1 : 0;
    return (start + step) % count;
}
