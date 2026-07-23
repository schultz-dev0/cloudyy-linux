.pragma library

function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
}

function emptySnapshot() {
    return {
        polkit_ready: false,
        polkit_message: "",
        offline_places_available: false,
        offline_places_message: "",
        timezone: "",
        timezone_label: "—",
        local_clock: "—",
        ntp_enabled: true,
        ntp_sync: "unknown",
        ntp_service: "unknown",
        ntp_status_label: "—",
        geo_active: false,
        geo_service_label: "—",
        manual_location: false,
        saved_mode: "auto",
        saved_lat: "",
        saved_lon: "",
        static_location: null,
        location: null,
        location_label: "—",
        clock: { year: 1970, month: 1, day: 1, hour: 0, minute: 0, second: 0 },
        stale: false,
        error: "",
        revision: 0,
    };
}

function pad2(value) {
    const n = Math.max(0, Math.floor(Number(value) || 0));
    return n < 10 ? "0" + n : String(n);
}

function weekdayName(year, month, day) {
    const names = [
        "Sunday", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday",
    ];
    const date = new Date(year, month - 1, day);
    return names[date.getDay()] || "";
}

function monthShort(month) {
    const names = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    return names[Math.max(0, Math.min(11, (Number(month) || 1) - 1))] || "";
}

function formatClock(clock) {
    if (!clock)
        return "—";
    const year = Number(clock.year) || 0;
    const month = Number(clock.month) || 1;
    const day = Number(clock.day) || 1;
    const hour = Number(clock.hour) || 0;
    const minute = Number(clock.minute) || 0;
    const second = Number(clock.second) || 0;
    const weekday = weekdayName(year, month, day);
    return weekday + ", " + pad2(day) + " " + monthShort(month) + " " + year
        + "  " + pad2(hour) + ":" + pad2(minute) + ":" + pad2(second);
}

function tickClock(clock) {
    const next = clone(clock || emptySnapshot().clock);
    next.second = Number(next.second || 0) + 1;
    if (next.second >= 60) {
        next.second = 0;
        next.minute = Number(next.minute || 0) + 1;
    }
    if (next.minute >= 60) {
        next.minute = 0;
        next.hour = Number(next.hour || 0) + 1;
    }
    if (next.hour >= 24) {
        next.hour = 0;
        const date = new Date(next.year, next.month - 1, next.day);
        date.setDate(date.getDate() + 1);
        next.year = date.getFullYear();
        next.month = date.getMonth() + 1;
        next.day = date.getDate();
    }
    return next;
}

function filterTimezones(zones, query) {
    const list = Array.isArray(zones) ? zones : [];
    const q = String(query || "").trim().toLowerCase();
    if (!q)
        return list;
    return list.filter(item => {
        const id = String(item.id || item.label || "").toLowerCase();
        const offset = String(item.offset || "").toLowerCase();
        return id.indexOf(q) !== -1 || offset.indexOf(q) !== -1;
    });
}

function locationCoords(snapshot) {
    const loc = (snapshot && snapshot.location)
        || (snapshot && snapshot.static_location)
        || null;
    if (!loc)
        return { latitude: "", longitude: "", accuracy: "200" };
    return {
        latitude: String(loc.latitude ?? ""),
        longitude: String(loc.longitude ?? ""),
        accuracy: String(loc.accuracy ?? 200),
    };
}
