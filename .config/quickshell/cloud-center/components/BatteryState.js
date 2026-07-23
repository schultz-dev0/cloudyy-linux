.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
}

function emptySnapshot() {
    return {
        present: false,
        capabilities: { threshold: false, asus_mode: false },
        info: null,
        display: {},
        asus_modes: [],
        asus_mode_descriptions: [],
        stale: false,
        error: "",
        revision: 0,
    };
}

function percentage(snapshot) {
    const info = snapshot && snapshot.info;
    if (!info)
        return 0;
    return Number(info.percentage || 0);
}

function displayValue(snapshot, key, fallback) {
    const display = (snapshot && snapshot.display) || {};
    const value = display[key];
    if (value === undefined || value === null || value === "")
        return fallback;
    return String(value);
}

function hasCapability(snapshot, name) {
    const caps = (snapshot && snapshot.capabilities) || {};
    return caps[name] === true;
}

function chargeModeIndex(snapshot) {
    const info = snapshot && snapshot.info;
    if (!info || info.charge_mode === null || info.charge_mode === undefined)
        return -1;
    return Number(info.charge_mode);
}

function thresholdValue(snapshot) {
    const info = snapshot && snapshot.info;
    if (!info)
        return 100;
    const value = Number(info.charge_end_threshold);
    if (isNaN(value))
        return 100;
    return Math.max(40, Math.min(100, value));
}
