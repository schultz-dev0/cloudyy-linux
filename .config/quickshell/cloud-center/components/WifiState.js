.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function filterNetworks(networks, query) {
    const list = networks || [];
    const needle = String(query || "").trim().toLowerCase();
    if (!needle)
        return list.slice();
    return list.filter(item => String(item.ssid || "").toLowerCase().indexOf(needle) >= 0);
}

function stableSelection(networks, currentSsid) {
    const list = networks || [];
    const current = String(currentSsid || "");
    if (current && list.some(item => String(item.ssid) === current))
        return current;
    const connected = list.find(item => item.connected === true);
    return connected ? String(connected.ssid) : (list[0] ? String(list[0].ssid) : "");
}

function networkFor(networks, ssid) {
    const list = networks || [];
    const key = String(ssid || "");
    for (let index = 0; index < list.length; index++) {
        if (String(list[index].ssid) === key)
            return list[index];
    }
    return null;
}

function networkSubtitle(network) {
    if (!network)
        return "";
    const parts = [];
    if (network.connected)
        parts.push("Connected");
    else if (network.saved)
        parts.push("Saved");
    if (network.is_open)
        parts.push("Open network");
    else if (network.security && network.security !== "--")
        parts.push(String(network.security));
    if (network.frequency)
        parts.push(String(network.frequency));
    return parts.length ? parts.join(" · ") : "Available";
}

function detailSummary(network) {
    if (!network)
        return "";
    const parts = ["Signal " + String(network.signal || 0) + "%"];
    if (network.frequency)
        parts.push(String(network.frequency));
    if (network.is_open)
        parts.push("Open");
    else if (network.security && network.security !== "--")
        parts.push(String(network.security));
    return parts.join("  ·  ");
}

function statusLine(snapshot, networkCount) {
    const enabled = snapshot && snapshot.enabled === true;
    if (!enabled)
        return "Wi-Fi is turned off";
    const active = String((snapshot && snapshot.active_ssid) || "");
    const count = Number(networkCount || 0);
    if (active)
        return "Connected to " + active + "  ·  " + count + " visible";
    return count + " networks visible";
}

function emptyListMessage(enabled, query, filteredCount, totalCount) {
    if (!enabled)
        return "Turn Wi-Fi on to see nearby networks";
    const needle = String(query || "").trim();
    if (needle && filteredCount === 0)
        return "No networks match “" + needle + "”";
    if (totalCount === 0)
        return "No networks found — try Rescan";
    return "";
}

function signalBars(signal) {
    const value = Number(signal || 0);
    if (value >= 75)
        return "󰤨";
    if (value >= 50)
        return "󰤥";
    if (value >= 25)
        return "󰤢";
    return "󰤟";
}

function setPending(pending, key, generation, value) {
    const next = clone(pending || {});
    next[key] = { generation: generation, value: value };
    return next;
}

function clearCompleted(pending, key, generation) {
    const next = clone(pending || {});
    if (next[key] !== undefined && Number(next[key].generation) <= Number(generation))
        delete next[key];
    return next;
}

function displayValue(pending, key, fallback) {
    const item = (pending || {})[key];
    return item === undefined ? fallback : item.value;
}

function connectMode(network) {
    if (!network)
        return "none";
    if (network.is_enterprise)
        return "enterprise";
    if (network.saved || network.is_open)
        return "direct";
    return "password";
}
