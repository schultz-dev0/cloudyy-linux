.pragma library

function appearanceEnabled(values) {
    return values && values.enable_hyprcursor !== false;
}

function settingEnabled(key, values) {
    values = values || {};
    if (["zoom_rigid", "zoom_detached_camera", "zoom_disable_aa"].includes(key))
        return Number(values.zoom_factor ?? 1) > 1;
    if (key === "min_refresh_rate")
        return Number(values.no_break_fs_vrr ?? 0) !== 0;
    return true;
}
