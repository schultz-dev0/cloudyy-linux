import QtQuick

QtObject {
    id: drafts

    property var windowRules: []
    property var layerRules: []
    property var autostart: []
    property var envVars: []
    property string baselineJson: "{}"

    readonly property bool dirty: dirtySurfaces.length > 0
    readonly property var dirtySurfaces: {
        const baseline = JSON.parse(baselineJson || "{}");
        const result = [];
        if (JSON.stringify(windowRules) !== JSON.stringify(baseline.window_rules ?? [])
                || JSON.stringify(layerRules) !== JSON.stringify(baseline.layer_rules ?? []))
            result.push("windowrules");
        if (JSON.stringify(autostart) !== JSON.stringify(baseline.autostart ?? []))
            result.push("autostart");
        if (JSON.stringify(envVars) !== JSON.stringify(baseline.env_vars ?? []))
            result.push("variables");
        return result;
    }

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function currentData() {
        return {
            window_rules: clone(windowRules),
            layer_rules: clone(layerRules),
            autostart: clone(autostart),
            env_vars: clone(envVars),
        };
    }

    function load(data) {
        const clean = clone(data ?? {});
        windowRules = clean.window_rules ?? [];
        layerRules = clean.layer_rules ?? [];
        autostart = clean.autostart ?? [];
        envVars = clean.env_vars ?? [];
        baselineJson = JSON.stringify(currentData());
    }

    function discard() {
        load(JSON.parse(baselineJson || "{}"));
    }

    function valuesFor(collection) {
        if (collection === "window_rules") return windowRules;
        if (collection === "layer_rules") return layerRules;
        if (collection === "autostart") return autostart;
        return envVars;
    }

    function assign(collection, values) {
        if (collection === "window_rules") windowRules = values;
        else if (collection === "layer_rules") layerRules = values;
        else if (collection === "autostart") autostart = values;
        else envVars = values;
    }

    function replace(collection, index, value) {
        const values = clone(valuesFor(collection));
        if (index < 0 || index >= values.length) return;
        values[index] = clone(value);
        assign(collection, values);
    }

    function append(collection, value) {
        const values = clone(valuesFor(collection));
        values.push(clone(value));
        assign(collection, values);
    }

    function remove(collection, index) {
        const values = clone(valuesFor(collection));
        if (index < 0 || index >= values.length) return;
        values.splice(index, 1);
        assign(collection, values);
    }

    function move(collection, from, to) {
        const values = clone(valuesFor(collection));
        if (from < 0 || from >= values.length || to < 0 || to >= values.length || from === to)
            return;
        const item = values.splice(from, 1)[0];
        values.splice(to, 0, item);
        assign(collection, values);
    }
}
