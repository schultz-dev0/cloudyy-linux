.pragma library

function suggestedRuleName(window) {
    const raw = String(window.class || window.initialClass || window.title || "window-rule");
    const cleaned = raw
        .replace(/^org[.-]/i, "")
        .replace(/[^a-zA-Z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "")
        .toLowerCase();
    return cleaned || "window-rule";
}

function applyPickedWindow(name, matchers, window, isNew) {
    const windowClass = String(window.class || window.initialClass || "");
    const preserved = (matchers || []).filter(function(matcher) {
        return matcher.property !== "class" && matcher.property !== "xwayland";
    });
    return {
        name: isNew && String(name || "").trim() === ""
            ? suggestedRuleName(window) : name,
        matchers: [
            { property: "class", mode: "exact", value: windowClass },
            { property: "xwayland", mode: "exact", value: window.xwayland ? "on" : "off" },
        ].concat(preserved),
    };
}

function setMatcherValueInPlace(matchers, index, value) {
    if (index >= 0 && index < matchers.length)
        matchers[index].value = value;
    return matchers;
}
