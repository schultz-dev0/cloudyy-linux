.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
}

function emptySnapshot() {
    return {
        revision: 0,
        settings: {
            screenshots_dir: "",
            recordings_dir: "",
            rec_audio_mic: false,
            rec_audio_desktop: false,
            rec_mic_device: "",
            rec_desktop_device: "",
            rec_fps: 60,
            rec_codec: "",
            rec_filetype: "mp4",
            rec_filename_pattern: "",
            island_preview_ms: 7000,
            auto_copy: false,
            edit_command: "xdg-open",
        },
        audio_inputs: { mics: [], desktops: [] },
        recording: { active: false, out_file: "", selection: "" },
        gallery: [],
        stale: false,
        error: "",
    };
}

// Prepends a "System default" pseudo-device (empty name = let the tool pick)
// so the dropdown always has a selectable first entry even before any
// device is explicitly chosen.
function deviceOptions(devices) {
    return [{ name: "", description: "System default" }].concat(devices || []);
}

function deviceIndex(devices, selectedName) {
    const options = deviceOptions(devices);
    const index = options.findIndex(device => device.name === (selectedName || ""));
    return index >= 0 ? index : 0;
}

function formatBytes(bytes) {
    const value = Number(bytes) || 0;
    if (value < 1024)
        return value + " B";
    const units = ["KB", "MB", "GB", "TB"];
    let scaled = value / 1024;
    let unitIndex = 0;
    while (scaled >= 1024 && unitIndex < units.length - 1) {
        scaled /= 1024;
        unitIndex++;
    }
    return scaled.toFixed(scaled >= 10 ? 0 : 1) + " " + units[unitIndex];
}

function pad2(value) {
    return String(value).padStart(2, "0");
}

function formatTimestamp(mtimeMs) {
    const date = new Date(Number(mtimeMs) || 0);
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[date.getMonth()] + " " + date.getDate() + ", "
        + pad2(date.getHours()) + ":" + pad2(date.getMinutes());
}
