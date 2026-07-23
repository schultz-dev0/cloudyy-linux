.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function stableSelection(items, current, idField) {
    const list = items || [];
    if (list.some(item => String(item[idField]) === String(current)))
        return String(current);
    const connected = list.find(item => item.connected);
    const fallback = connected || list[0];
    return fallback ? String(fallback[idField]) : "";
}

function displayValue(pending, key, fallback) {
    const item = (pending || {})[key];
    return item === undefined ? fallback : item.value;
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

function sortDevices(devices) {
    const list = (devices || []).slice();
    list.sort((left, right) => {
        const leftConnected = left.connected ? 0 : 1;
        const rightConnected = right.connected ? 0 : 1;
        if (leftConnected !== rightConnected)
            return leftConnected - rightConnected;
        const leftPaired = left.paired ? 0 : 1;
        const rightPaired = right.paired ? 0 : 1;
        if (leftPaired !== rightPaired)
            return leftPaired - rightPaired;
        const leftName = String(left.display_name || left.name || left.address || "").toLowerCase();
        const rightName = String(right.display_name || right.name || right.address || "").toLowerCase();
        if (leftName < rightName)
            return -1;
        if (leftName > rightName)
            return 1;
        return 0;
    });
    return list;
}

function deviceSubtitle(device) {
    if (!device)
        return "";
    const parts = [];
    if (device.connected)
        parts.push("Connected");
    else if (device.paired)
        parts.push("Paired");
    else
        parts.push("Available");
    if (device.device_type)
        parts.push(String(device.device_type));
    return parts.join(" · ");
}

function statusSummary(snapshot) {
    const data = snapshot || {};
    if (data.scanning)
        return "Scanning for nearby devices…";
    if (!data.powered)
        return "Bluetooth is off";
    const devices = data.devices || [];
    const connected = devices.filter(item => item.connected).length;
    if (devices.length === 0)
        return "No devices found — try Scan";
    return devices.length + " devices · " + connected + " connected";
}

function emptyListMessage(snapshot) {
    const data = snapshot || {};
    if (!data.powered)
        return "Turn Bluetooth on to see devices";
    if (data.scanning)
        return "Looking for nearby devices…";
    return "No devices found — try Scan";
}
