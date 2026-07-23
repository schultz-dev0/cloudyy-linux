.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
}

function filterPlugins(plugins, query, enabledOnly) {
    const list = Array.isArray(plugins) ? plugins : [];
    const needle = String(query || "").trim().toLowerCase();
    const out = [];
    for (let i = 0; i < list.length; i++) {
        const plugin = list[i];
        if (enabledOnly && plugin.enabled !== true)
            continue;
        if (needle) {
            const name = String(plugin.name || "").toLowerCase();
            const desc = String(plugin.desc || "").toLowerCase();
            if (name.indexOf(needle) === -1 && desc.indexOf(needle) === -1)
                continue;
        }
        out.push(plugin);
        if (out.length >= 100)
            break;
    }
    return out;
}

function description(plugin) {
    const desc = plugin && plugin.desc;
    if (desc === undefined || desc === null || String(desc).trim() === "")
        return "No description available.";
    return String(desc);
}
