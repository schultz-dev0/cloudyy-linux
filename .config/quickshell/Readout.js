.pragma library

// Bracketed mono readout grammar. See ~/Dev/cloudyy_visual/VISUAL-LANGUAGE.md §3.

function pair(key, value) {
    return "[ " + String(key) + " · " + String(value) + " ]";
}

function osd(key, value) {
    return "[ " + String(key) + " " + String(value) + " ]";
}

function pad2(n) {
    const s = String(Math.max(0, Math.floor(n)));
    return s.length < 2 ? "0" + s : s;
}

function mmss(seconds) {
    const t = Math.max(0, Math.floor(seconds));
    const m = Math.floor(t / 60);
    const s = t % 60;
    return pad2(m) + ":" + pad2(s);
}

function toSeconds(value) {
    if (!Number.isFinite(value) || value < 0)
        return -1;
    // Quickshell MprisPlayer is seconds; some exporters send microseconds.
    if (value > 100000)
        return value / 1e6;
    return value;
}

function identity(player) {
    if (!player)
        return "player";
    let raw = String(player.identity || player.desktopEntry || "player").trim();
    if (raw.indexOf(" ") >= 0)
        raw = raw.split(/\s+/)[0];
    else if (raw.indexOf(".") >= 0) {
        const slash = raw.lastIndexOf(".");
        if (slash >= 0 && slash < raw.length - 1)
            raw = raw.slice(slash + 1);
    }
    raw = raw.toLowerCase();
    if (raw.length > 12)
        raw = raw.slice(0, 12);
    return raw.length ? raw : "player";
}

function mpris(player) {
    const id = identity(player);
    if (!player)
        return pair(id, "00:00");
    const pos = toSeconds(Number(player.position));
    const len = player.lengthSupported ? toSeconds(Number(player.length)) : -1;
    if (pos < 0)
        return pair(id, "00:00");
    if (len <= 0)
        return pair(id, mmss(pos));
    return pair(id, mmss(pos) + " / " + mmss(len));
}

function osdLabel(kind, volumeValue, volumeMuted, brightnessValue, kbdValue, kbdMax, nightLightTemp) {
    if (kind === "brightness")
        return osd("BRT", Math.round(brightnessValue) + "%");
    if (kind === "kbdbrightness") {
        const pct = kbdMax > 0 ? kbdValue / kbdMax * 100 : 0;
        return osd("KBD", Math.round(pct) + "%");
    }
    if (kind === "nightlight")
        return osd("NL", nightLightTemp + "K");
    if (volumeMuted)
        return osd("VOL", "MUTE");
    return osd("VOL", Math.round(volumeValue) + "%");
}
