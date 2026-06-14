//! The write half of HCM: schema, on-disk state, render, and the `set` /
//! `reset-page` pipeline. Replaces `hypr_persist_lua.py`.
//!
//! The `user_*.lua` sentinel (`-- @cloud-center-state = {json}`) is the only
//! authoritative source of state — the old `.cloud-center-state.json` parallel
//! store is gone, which is the main reason this rewrite exists.

use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{anyhow, Context, Result};
use serde::Serialize;

use crate::runtime;

// ── Filesystem layout ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct HyprDirs {
    pub root: PathBuf,
}

impl HyprDirs {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// `$HOME/.config/hypr`.
    pub fn current() -> Self {
        let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
        Self::new(home.join(".config").join("hypr"))
    }

    pub fn root(&self) -> &Path { &self.root }
    pub fn source_dir(&self) -> PathBuf { self.root.join("source") }
    pub fn user_dir(&self) -> PathBuf { self.root.join("user-configs") }
    pub fn main_lua(&self) -> PathBuf { self.root.join("hyprland.lua") }

    /// Path to the `user_<name>` override for a given `source/<name>` module.
    pub fn user_module_for(&self, source_file: &Path) -> PathBuf {
        let name = source_file.file_name().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        self.user_dir().join(format!("user_{name}"))
    }
}

// ── Schema ──────────────────────────────────────────────────────────────────
//
// LAYOUT is the single source of truth for which CLI keys map to which Lua
// table path. Insertion order matters — render passes iterate in declaration
// order to produce stable output matching the Python implementation. Don't
// switch to a BTreeMap.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LayoutEntry {
    pub section: &'static str,
    pub subsection: Option<&'static str>,
    pub config_key: &'static str,
}

pub const LAYOUT: &[(&str, LayoutEntry)] = &[
    ("general:border_size",        LayoutEntry { section: "general",    subsection: None,             config_key: "border_size" }),
    ("general:gaps_out",           LayoutEntry { section: "general",    subsection: None,             config_key: "gaps_out" }),
    ("general:gaps_in",            LayoutEntry { section: "general",    subsection: None,             config_key: "gaps_in" }),
    ("decoration:rounding",        LayoutEntry { section: "decoration", subsection: None,             config_key: "rounding" }),
    ("decoration:active_opacity",  LayoutEntry { section: "decoration", subsection: None,             config_key: "active_opacity" }),
    ("decoration:inactive_opacity",LayoutEntry { section: "decoration", subsection: None,             config_key: "inactive_opacity" }),
    ("decoration:shadow:enabled",  LayoutEntry { section: "decoration", subsection: Some("shadow"),   config_key: "enabled" }),
    ("decoration:shadow:range",    LayoutEntry { section: "decoration", subsection: Some("shadow"),   config_key: "range" }),
    ("decoration:shadow:render_power", LayoutEntry { section: "decoration", subsection: Some("shadow"), config_key: "render_power" }),
    ("decoration:blur:enabled",    LayoutEntry { section: "decoration", subsection: Some("blur"),     config_key: "enabled" }),
    ("decoration:blur:passes",     LayoutEntry { section: "decoration", subsection: Some("blur"),     config_key: "passes" }),
    ("decoration:blur:size",       LayoutEntry { section: "decoration", subsection: Some("blur"),     config_key: "size" }),
    ("animations:enabled",         LayoutEntry { section: "animations", subsection: None,             config_key: "enabled" }),
    ("animations:bezier",          LayoutEntry { section: "animations", subsection: None,             config_key: "bezier" }),
    ("animations:animation",       LayoutEntry { section: "animations", subsection: None,             config_key: "animation" }),
    ("input:kb_layout",            LayoutEntry { section: "input",      subsection: None,             config_key: "kb_layout" }),
    ("input:kb_variant",           LayoutEntry { section: "input",      subsection: None,             config_key: "kb_variant" }),
    ("input:kb_model",             LayoutEntry { section: "input",      subsection: None,             config_key: "kb_model" }),
    ("input:kb_options",           LayoutEntry { section: "input",      subsection: None,             config_key: "kb_options" }),
    ("input:kb_rules",             LayoutEntry { section: "input",      subsection: None,             config_key: "kb_rules" }),
    ("input:repeat_delay",         LayoutEntry { section: "input",      subsection: None,             config_key: "repeat_delay" }),
    ("input:repeat_rate",          LayoutEntry { section: "input",      subsection: None,             config_key: "repeat_rate" }),
    ("input:follow_mouse",         LayoutEntry { section: "input",      subsection: None,             config_key: "follow_mouse" }),
    ("input:sensitivity",          LayoutEntry { section: "input",      subsection: None,             config_key: "sensitivity" }),
    ("input:accel_profile",        LayoutEntry { section: "input",      subsection: None,             config_key: "accel_profile" }),
    ("input:natural_scroll",       LayoutEntry { section: "input",      subsection: None,             config_key: "natural_scroll" }),
    ("input:numlock_by_default",   LayoutEntry { section: "input",      subsection: None,             config_key: "numlock_by_default" }),
    ("input:touchpad:natural_scroll",      LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "natural_scroll" }),
    ("input:touchpad:disable_while_typing",LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "disable_while_typing" }),
    ("input:touchpad:tap-to-click",        LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "tap-to-click" }),
    ("input:touchpad:clickfinger_behavior",LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "clickfinger_behavior" }),
    ("input:touchpad:middle_button_emulation", LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "middle_button_emulation" }),
    ("input:touchpad:scroll_factor",       LayoutEntry { section: "input", subsection: Some("touchpad"), config_key: "scroll_factor" }),
    ("cursor:no_hardware_cursors", LayoutEntry { section: "cursor",     subsection: None,             config_key: "no_hardware_cursors" }),
    ("cursor:enable_hyprcursor",   LayoutEntry { section: "cursor",     subsection: None,             config_key: "enable_hyprcursor" }),
    ("cursor:no_warps",            LayoutEntry { section: "cursor",     subsection: None,             config_key: "no_warps" }),
    ("cursor:persistent_warps",    LayoutEntry { section: "cursor",     subsection: None,             config_key: "persistent_warps" }),
    ("cursor:warp_on_change_workspace", LayoutEntry { section: "cursor", subsection: None,            config_key: "warp_on_change_workspace" }),
    ("cursor:zoom_factor",         LayoutEntry { section: "cursor",     subsection: None,             config_key: "zoom_factor" }),
    ("cursor:zoom_rigid",          LayoutEntry { section: "cursor",     subsection: None,             config_key: "zoom_rigid" }),
    ("cursor:inactive_timeout",    LayoutEntry { section: "cursor",     subsection: None,             config_key: "inactive_timeout" }),
    ("cursor:hide_on_key_press",   LayoutEntry { section: "cursor",     subsection: None,             config_key: "hide_on_key_press" }),
    ("cursor:hide_on_touch",       LayoutEntry { section: "cursor",     subsection: None,             config_key: "hide_on_touch" }),
    ("cursor:hide_on_tablet",      LayoutEntry { section: "cursor",     subsection: None,             config_key: "hide_on_tablet" }),
    ("cursor:no_break_fs_vrr",     LayoutEntry { section: "cursor",     subsection: None,             config_key: "no_break_fs_vrr" }),
    ("cursor:hotspot_padding",     LayoutEntry { section: "cursor",     subsection: None,             config_key: "hotspot_padding" }),
];

const SURFACES: &[&str] = &["lookandfeel", "animations", "input", "cursor"];

const LEGACY_CONFS: &[(&str, &str)] = &[
    ("lookandfeel", "user_lookandfeel.conf"),
    ("animations", "user_animations.conf"),
    ("input", "user_input.conf"),
    ("cursor", "user_cursor.conf"),
];

const SENTINEL_PREFIX: &str = "-- @cloud-center-state = ";

const PAGE_HYPRLAND: &[&str] = &[
    "general:border_size", "general:gaps_out", "general:gaps_in",
    "decoration:rounding", "decoration:active_opacity", "decoration:inactive_opacity",
    "decoration:shadow:enabled", "decoration:shadow:range", "decoration:shadow:render_power",
    "decoration:blur:enabled", "decoration:blur:passes", "decoration:blur:size",
    "animations:enabled", "animations:bezier", "animations:animation",
];

const PAGE_INPUT: &[&str] = &[
    "input:kb_layout", "input:kb_variant", "input:kb_model",
    "input:kb_options", "input:kb_rules", "input:repeat_delay",
    "input:repeat_rate", "input:follow_mouse", "input:sensitivity",
    "input:accel_profile", "input:natural_scroll", "input:numlock_by_default",
    "input:touchpad:natural_scroll", "input:touchpad:disable_while_typing",
    "input:touchpad:tap-to-click", "input:touchpad:clickfinger_behavior",
    "input:touchpad:middle_button_emulation", "input:touchpad:scroll_factor",
];

const PAGE_CURSOR: &[&str] = &[
    "cursor:no_hardware_cursors", "cursor:enable_hyprcursor",
    "cursor:no_warps", "cursor:persistent_warps",
    "cursor:warp_on_change_workspace", "cursor:zoom_factor",
    "cursor:zoom_rigid", "cursor:inactive_timeout",
    "cursor:hide_on_key_press", "cursor:hide_on_touch",
    "cursor:hide_on_tablet", "cursor:no_break_fs_vrr",
    "cursor:hotspot_padding",
];

fn lookup(key: &str) -> Option<&'static LayoutEntry> {
    LAYOUT.iter().find(|(k, _)| *k == key).map(|(_, v)| v)
}

fn page(name: &str) -> Option<&'static [&'static str]> {
    match name {
        "hyprland" => Some(PAGE_HYPRLAND),
        "input" => Some(PAGE_INPUT),
        "cursor" => Some(PAGE_CURSOR),
        _ => None,
    }
}

fn user_filename(surface: &str) -> Option<&'static str> {
    match surface {
        "lookandfeel" => Some("user_lookandfeel.lua"),
        "animations" => Some("user_animations.lua"),
        "input" => Some("user_input.lua"),
        "cursor" => Some("user_cursor.lua"),
        _ => None,
    }
}

fn sections_of(surface: &str) -> &'static [&'static str] {
    match surface {
        "lookandfeel" => &["general", "decoration"],
        "animations" => &["animations"],
        "input" => &["input"],
        "cursor" => &["cursor"],
        _ => &[],
    }
}

/// Returns the surface that owns the given key, e.g.
/// `surface_of("decoration:rounding") == Some("lookandfeel")`.
fn surface_of(key: &str) -> Option<&'static str> {
    let section = lookup(key)?.section;
    match section {
        "general" | "decoration" => Some("lookandfeel"),
        "animations" => Some("animations"),
        "input" => Some("input"),
        "cursor" => Some("cursor"),
        _ => None,
    }
}

// ── Crash-safe writes ───────────────────────────────────────────────────────
//
// Python's `atomic_write` used `os.replace` without any fsync; this version
// fsyncs both the temp file and the parent directory so a power-loss or
// OOM-kill between steps can't leave a half-written or invisible file.

pub fn atomic_write(path: &Path, content: &[u8]) -> io::Result<()> {
    let parent = path.parent().ok_or_else(|| io::Error::new(
        io::ErrorKind::InvalidInput, format!("no parent for {}", path.display())))?;
    fs::create_dir_all(parent)?;

    let name = path.file_name().ok_or_else(|| io::Error::new(
        io::ErrorKind::InvalidInput, format!("no file name for {}", path.display())))?;
    let mut tmp_name = name.to_os_string();
    tmp_name.push(".tmp");
    let tmp = parent.join(tmp_name);

    {
        let mut f = OpenOptions::new().write(true).create(true).truncate(true).open(&tmp)?;
        f.write_all(content)?;
        f.sync_all()?;
    }

    if let Err(e) = fs::rename(&tmp, path) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    if let Ok(dir) = File::open(parent) {
        let _ = dir.sync_all();
    }
    Ok(())
}

// ── State map ───────────────────────────────────────────────────────────────

pub type State = BTreeMap<String, String>;

/// Merge state from every `user_*.lua` sentinel, falling back to legacy
/// `.conf` parsing only if no sentinel exists.
pub fn load(dirs: &HyprDirs) -> State {
    let user_dir = dirs.user_dir();
    let mut state = State::new();
    let mut found_managed = false;

    for surface in SURFACES {
        let Some(name) = user_filename(surface) else { continue };
        let (present, parsed) = read_sentinel(&user_dir.join(name));
        if present { found_managed = true; }
        for (k, v) in parsed {
            if lookup(&k).is_some() { state.insert(k, v); }
        }
    }

    if !found_managed {
        for (_, fname) in LEGACY_CONFS {
            for (k, v) in read_legacy_conf(&user_dir.join(fname)) {
                if lookup(&k).is_some() { state.insert(k, v); }
            }
        }
    }
    state
}

/// `(sentinel_present, parsed_map)`. Returns `(false, empty)` when the file
/// doesn't exist or has no sentinel.
pub fn read_sentinel(path: &Path) -> (bool, State) {
    let Ok(text) = fs::read_to_string(path) else { return (false, State::new()) };
    for line in text.lines().take(5) {
        let Some(json) = line.strip_prefix(SENTINEL_PREFIX) else { continue };
        let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else { continue };
        let Some(obj) = value.as_object() else { continue };

        let mut out = State::new();
        for (k, v) in obj {
            // Coerce every value to string, defensively — sentinels always
            // store strings in practice, but the parser shouldn't trust that.
            let s = match v {
                serde_json::Value::String(s) => s.clone(),
                other => other.to_string(),
            };
            out.insert(k.clone(), s);
        }
        return (true, out);
    }
    (false, State::new())
}

fn read_legacy_conf(path: &Path) -> State {
    let mut result = State::new();
    let Ok(text) = fs::read_to_string(path) else { return result };

    let by_path: BTreeMap<(&str, Option<&str>, &str), &str> = LAYOUT.iter()
        .map(|(k, e)| ((e.section, e.subsection, e.config_key), *k))
        .collect();

    let mut section: Option<String> = None;
    let mut sub: Option<String> = None;
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') { continue; }

        if let Some(name) = line.strip_suffix('{').map(str::trim_end) {
            let name = name.trim();
            let is_ident = !name.is_empty()
                && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == ':');
            if is_ident {
                if section.is_none() { section = Some(name.into()); }
                else if sub.is_none() { sub = Some(name.into()); }
                continue;
            }
        }
        if line == "}" {
            if sub.is_some() { sub = None; } else { section = None; }
            continue;
        }
        let Some(eq) = line.find('=') else { continue };
        let lhs = line[..eq].trim_end();
        let rhs = &line[eq + 1..];
        let Some(sec) = section.as_deref() else { continue };
        if let Some(canonical) = by_path.get(&(sec, sub.as_deref(), lhs)) {
            result.insert((*canonical).to_string(), rhs.trim().to_string());
        }
    }
    result
}

// ── Lua rendering ───────────────────────────────────────────────────────────
//
// Output is byte-identical to Python's `build_surface_content` — an existing
// managed config rewritten by `hcm set` is a no-op diff.

/// Full file contents for `user_SURFACE.lua` given the current state map.
pub fn render_surface(state: &State, surface: &str) -> String {
    let owned: Vec<(&'static str, String)> = LAYOUT.iter()
        .filter_map(|(k, _)| {
            (surface_of(k) == Some(surface))
                .then(|| state.get(*k).map(|v| (*k, v.clone())))
                .flatten()
        })
        .collect();

    let mut lines = vec![
        format!("-- Cloud Center user override file for {surface} configuration."),
        format!("{SENTINEL_PREFIX}{}", sentinel_json(&owned)),
    ];

    // lookandfeel / animations / input pull in the distro source first, then
    // layer overrides on top. cursor is a full replacement.
    if matches!(surface, "lookandfeel" | "animations" | "input") {
        lines.push(String::new());
        lines.push(format!("require(\"source.{surface}\")"));
    }

    let body = if surface == "animations" {
        render_animation_body(state)
    } else {
        render_table(state, surface)
    };
    if !body.is_empty() {
        lines.push(String::new());
        lines.extend(body);
    }

    let mut out = lines.join("\n");
    out.push('\n');
    out
}

fn render_animation_body(state: &State) -> Vec<String> {
    let mut body = Vec::new();
    if let Some(v) = state.get("animations:enabled") {
        body.push(format!("hl.config({{ animations = {{ enabled = {} }} }})", lua_value(v)));
    }
    if let Some(v) = state.get("animations:bezier") {
        if let Some(line) = render_curve(v) { body.push(line); }
    }
    if let Some(v) = state.get("animations:animation") {
        if let Some(line) = render_animation(v) { body.push(line); }
    }
    body
}

/// Render the `hl.config({...})` table for non-animation surfaces.
fn render_table(state: &State, surface: &str) -> Vec<String> {
    let sections = sections_of(surface);
    if sections.is_empty() { return Vec::new(); }

    let pick = |section: &str| -> Vec<(&'static LayoutEntry, &str)> {
        LAYOUT.iter()
            .filter(|(k, e)| e.section == section && surface_of(k) == Some(surface) && state.contains_key(*k))
            .map(|(k, e)| (e, state.get(*k).unwrap().as_str()))
            .collect()
    };

    if sections.iter().all(|s| pick(s).is_empty()) { return Vec::new(); }

    let mut lines = vec!["hl.config({".to_string()];
    for section in sections {
        let entries = pick(section);
        if entries.is_empty() { continue; }
        lines.push(format!("    {section} = {{"));

        // Top-level keys first.
        for (e, v) in entries.iter().filter(|(e, _)| e.subsection.is_none()) {
            lines.push(format!("        {} = {},", lua_key(e.config_key), lua_value(v)));
        }
        // Then each subsection in LAYOUT order, deduped.
        let mut subs: Vec<&'static str> = Vec::new();
        for (e, _) in entries.iter().filter(|(e, _)| e.subsection.is_some()) {
            let sub = e.subsection.unwrap();
            if !subs.contains(&sub) { subs.push(sub); }
        }
        for sub in subs {
            lines.push(format!("        {sub} = {{"));
            for (e, v) in entries.iter().filter(|(e, _)| e.subsection == Some(sub)) {
                lines.push(format!("            {} = {},", lua_key(e.config_key), lua_value(v)));
            }
            lines.push("        },".to_string());
        }
        lines.push("    },".to_string());
    }
    lines.push("})".to_string());
    lines
}

/// Parse `name,x1,y1,x2,y2` into an `hl.curve(...)` call.
fn render_curve(value: &str) -> Option<String> {
    let parts: Vec<&str> = value.split(',').map(str::trim).collect();
    if parts.len() != 5 { return None; }
    let (name, x1, y1, x2, y2) = (parts[0], parts[1], parts[2], parts[3], parts[4]);
    Some(format!(
        "hl.curve({}, {{ type = \"bezier\", points = {{ {{ {x1}, {y1} }}, {{ {x2}, {y2} }} }} }})",
        lua_value(name)
    ))
}

/// Parse `leaf,enabled,speed,bezier[,style…]` into an `hl.animation(...)` call.
fn render_animation(value: &str) -> Option<String> {
    let parts: Vec<&str> = value.split(',').map(str::trim).collect();
    if parts.len() < 4 { return None; }
    let (leaf, enabled, speed, bezier) = (parts[0], parts[1], parts[2], parts[3]);
    let enabled_lua = if enabled == "1" || enabled == "true" { "true" } else { "false" };
    let mut fields = vec![
        format!("leaf = {}", lua_value(leaf)),
        format!("enabled = {enabled_lua}"),
        format!("speed = {}", lua_value(speed)),
        format!("bezier = {}", lua_value(bezier)),
    ];
    if parts.len() > 4 {
        fields.push(format!("style = {}", lua_value(&parts[4..].join(","))));
    }
    Some(format!("hl.animation({{ {} }})", fields.join(", ")))
}

/// `true`/`false` and Python's NUMBER_RE pass through; everything else is JSON
/// double-quoted.
fn lua_value(v: &str) -> String {
    if v == "true" || v == "false" { return v.into(); }
    if is_numeric(v) { return v.into(); }
    serde_json::to_string(v).expect("string serialization cannot fail")
}

// `^-?(?:\d+\.\d+|\d+|\.\d+)$`
fn is_numeric(s: &str) -> bool {
    let body = s.strip_prefix('-').unwrap_or(s);
    if body.is_empty() || body == "." { return false; }
    body.bytes().filter(|b| *b == b'.').count() <= 1
        && body.bytes().all(|b| b.is_ascii_digit() || b == b'.')
}

/// Bare identifiers stay bare; everything else becomes `["…"]`.
fn lua_key(k: &str) -> String {
    let mut bytes = k.bytes();
    let bare = match bytes.next() {
        Some(b) if b.is_ascii_alphabetic() || b == b'_' => {
            bytes.all(|c| c.is_ascii_alphanumeric() || c == b'_')
        }
        _ => false,
    };
    if bare { k.into() } else { format!("[{}]", serde_json::to_string(k).unwrap()) }
}

/// Mirror Python `json.dumps(dict, sort_keys=True)`: alphabetical keys, `", "`
/// between pairs, `": "` between key/value, every value double-quoted.
fn sentinel_json(entries: &[(&'static str, String)]) -> String {
    let mut sorted: Vec<(&str, &str)> = entries.iter().map(|(k, v)| (*k, v.as_str())).collect();
    sorted.sort_by(|a, b| a.0.cmp(b.0));

    let mut out = String::from("{");
    for (i, (k, v)) in sorted.iter().enumerate() {
        if i > 0 { out.push_str(", "); }
        out.push_str(&serde_json::to_string(k).unwrap());
        out.push_str(": ");
        out.push_str(&serde_json::to_string(v).unwrap());
    }
    out.push('}');
    out
}

// ── Live apply (hyprctl eval) ───────────────────────────────────────────────
//
// Hyprland 0.55+ Lua configs reject `hyprctl keyword` (it prints an error but
// still exits 0). Cloud Center calls `hcm apply` instead, which persists then
// runs the equivalent `hl.config` / `hl.curve` / `hl.animation` eval.

/// Build a `hyprctl eval` expression for a managed config key.
pub fn build_live_eval(key: &str, value: &str) -> Option<String> {
    match key {
        "animations:bezier" => return render_curve(value),
        "animations:animation" => return render_animation(value),
        _ => {}
    }

    let entry = lookup(key)?;
    let v = lua_value(value);
    let ck = eval_config_key(entry.config_key);

    Some(if let Some(sub) = entry.subsection {
        format!(
            "hl.config({{ {} = {{ {} = {{ {} = {} }} }} }})",
            entry.section, sub, ck, v
        )
    } else {
        format!(
            "hl.config({{ {} = {{ {} = {} }} }})",
            entry.section, ck, v
        )
    })
}

/// Lua eval keys use underscores; persisted files may use quoted hyphenated keys.
fn eval_config_key(k: &str) -> String {
    lua_key(&k.replace('-', "_"))
}

fn hyprctl_eval_ok(expr: &str) -> bool {
    let Ok(out) = Command::new("hyprctl").args(["eval", expr]).output() else {
        return false;
    };
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr),
    );
    !combined.contains("error:")
        && !combined.contains("keyword can't work")
        && !combined.contains("attempt to call a nil value")
}

fn reload_hyprland() {
    let _ = Command::new("hyprctl").args(["reload"]).output();
}

/// Persist a key, then apply it live via `hyprctl eval` (reload on eval failure).
pub fn apply(dirs: &HyprDirs, key: &str, value: &str) -> Result<Outcome> {
    let outcome = set(dirs, key, value)?;
    if let Some(expr) = build_live_eval(key, value) {
        if hyprctl_eval_ok(&expr) {
            eprintln!("[hcm] applied live: {key} = {value}");
        } else {
            eprintln!("[hcm] live eval failed for {key}, reloading Hyprland");
            reload_hyprland();
        }
    }
    Ok(outcome)
}

// ── set / reset-page pipeline ───────────────────────────────────────────────

/// JSON wire shape for `set` and `reset-page`.
#[derive(Debug, Clone, Serialize)]
pub struct Outcome {
    pub ok: bool,
    pub message: String,
    pub touched_surfaces: Vec<&'static str>,
    pub written: Vec<PathBuf>,
    pub removed: Vec<PathBuf>,
}

pub fn set(dirs: &HyprDirs, key: &str, value: &str) -> Result<Outcome> {
    if lookup(key).is_none() {
        eprintln!("[hcm] WARNING: unsupported key '{key}', skipping");
        return Ok(Outcome {
            ok: true,
            message: format!("Ignored unsupported key '{key}'"),
            touched_surfaces: vec![],
            written: vec![],
            removed: vec![],
        });
    }

    let mut state = load(dirs);
    state.insert(key.into(), value.into());
    let touched: Vec<&'static str> = surface_of(key).into_iter().collect();

    let (written, removed) = commit(dirs, &state, &touched)?;
    let _ = runtime::archive_legacy(dirs); // best-effort, matches Python

    let message = format!("persisted {key} = {value}");
    eprintln!("[hcm] {message}");
    Ok(Outcome { ok: true, message, touched_surfaces: touched, written, removed })
}

pub fn reset_page(dirs: &HyprDirs, name: &str) -> Result<Outcome> {
    let keys = page(name).ok_or_else(|| anyhow!("unknown page '{name}'"))?;

    let mut state = load(dirs);
    let mut touched: Vec<&'static str> = Vec::new();
    for k in keys {
        state.remove(*k);
        if let Some(s) = surface_of(k) {
            if !touched.contains(&s) { touched.push(s); }
        }
    }

    let (written, removed) = commit(dirs, &state, &touched)?;
    let _ = runtime::archive_legacy(dirs);

    let message = format!("reset-page {name}");
    eprintln!("[hcm] {message}");
    Ok(Outcome { ok: true, message, touched_surfaces: touched, written, removed })
}

/// Write each touched `user_*.lua` (or delete it if no state remains for that
/// surface) and update the activation lines in `hyprland.lua`.
fn commit(dirs: &HyprDirs, state: &State, touched: &[&'static str])
    -> Result<(Vec<PathBuf>, Vec<PathBuf>)>
{
    let mut written = Vec::new();
    let mut removed = Vec::new();
    let user_dir = dirs.user_dir();

    for surface in touched {
        let Some(filename) = user_filename(surface) else { continue };
        let path = user_dir.join(filename);
        let has_state = state.keys().any(|k| surface_of(k) == Some(surface));
        if has_state {
            atomic_write(&path, render_surface(state, surface).as_bytes())
                .with_context(|| format!("write {}", path.display()))?;
            eprintln!("[hcm] wrote {}", path.display());
            written.push(path);
        } else if path.exists() {
            fs::remove_file(&path).with_context(|| format!("remove {}", path.display()))?;
            eprintln!("[hcm] removed {}", path.display());
            removed.push(path);
        }
    }

    let main_lua = dirs.main_lua();
    if !main_lua.exists() {
        eprintln!("[hcm] WARNING: {} not found — activation lines unchanged", main_lua.display());
        return Ok((written, removed));
    }
    let mut text = fs::read_to_string(&main_lua).with_context(|| format!("read {}", main_lua.display()))?;
    for surface in touched {
        let has_state = state.keys().any(|k| surface_of(k) == Some(surface));
        text = if has_state {
            runtime::activate_user(&text, surface)
        } else {
            runtime::activate_source(&text, surface)
        };
    }
    atomic_write(&main_lua, text.as_bytes()).with_context(|| format!("write {}", main_lua.display()))?;
    eprintln!("[hcm] updated activation lines in {}", main_lua.display());

    Ok((written, removed))
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    // -- atomic_write ---------------------------------------------------------

    #[test]
    fn atomic_replaces_existing() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("a.txt");
        fs::write(&p, "old").unwrap();
        atomic_write(&p, b"new").unwrap();
        assert_eq!(fs::read(&p).unwrap(), b"new");
        assert!(!dir.path().join("a.txt.tmp").exists());
    }

    #[test]
    fn atomic_creates_parent_dirs() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("nested/sub/a.txt");
        atomic_write(&p, b"x").unwrap();
        assert_eq!(fs::read(&p).unwrap(), b"x");
    }

    // -- Schema ---------------------------------------------------------------

    #[test]
    fn layout_matches_python_count() {
        assert_eq!(LAYOUT.len(), 46);
    }

    #[test]
    fn surface_of_known_keys() {
        assert_eq!(surface_of("general:gaps_in"), Some("lookandfeel"));
        assert_eq!(surface_of("decoration:blur:enabled"), Some("lookandfeel"));
        assert_eq!(surface_of("animations:animation"), Some("animations"));
        assert_eq!(surface_of("input:touchpad:tap-to-click"), Some("input"));
        assert_eq!(surface_of("cursor:hotspot_padding"), Some("cursor"));
        assert_eq!(surface_of("nonsense"), None);
    }

    // -- lua_value / lua_key --------------------------------------------------

    #[test]
    fn lua_value_pass_through_for_bools_and_numbers() {
        assert_eq!(lua_value("true"), "true");
        assert_eq!(lua_value("false"), "false");
        assert_eq!(lua_value("42"), "42");
        assert_eq!(lua_value("-1"), "-1");
        assert_eq!(lua_value("1.5"), "1.5");
        assert_eq!(lua_value(".5"), ".5");
        assert_eq!(lua_value("hello"), "\"hello\"");
    }

    #[test]
    fn lua_key_quotes_when_needed() {
        assert_eq!(lua_key("repeat_rate"), "repeat_rate");
        assert_eq!(lua_key("tap-to-click"), "[\"tap-to-click\"]");
    }

    // -- Sentinel I/O ---------------------------------------------------------

    fn write_at(p: &Path, s: &str) {
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, s).unwrap();
    }

    #[test]
    fn read_sentinel_real_world() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("user_lookandfeel.lua");
        write_at(&p,
            "-- Cloud Center user override file for lookandfeel configuration.\n\
             -- @cloud-center-state = {\"decoration:blur:enabled\": \"true\", \"general:gaps_in\": \"0\"}\n\
             \n\
             require(\"source.lookandfeel\")\n");
        let (present, state) = read_sentinel(&p);
        assert!(present);
        assert_eq!(state.get("general:gaps_in").map(String::as_str), Some("0"));
    }

    #[test]
    fn load_unions_all_surfaces() {
        let dir = tempdir().unwrap();
        let dirs = HyprDirs::new(dir.path());
        let udir = dirs.user_dir();
        write_at(&udir.join("user_lookandfeel.lua"),
            "-- header\n-- @cloud-center-state = {\"general:gaps_in\": \"0\"}\n");
        write_at(&udir.join("user_cursor.lua"),
            "-- header\n-- @cloud-center-state = {\"cursor:zoom_factor\": \"1\"}\n");
        let state = load(&dirs);
        assert_eq!(state.get("general:gaps_in").map(String::as_str), Some("0"));
        assert_eq!(state.get("cursor:zoom_factor").map(String::as_str), Some("1"));
    }

    // -- Render snapshots: byte-for-byte against the user's real files.

    fn entries(pairs: &[(&str, &str)]) -> State {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn render_lookandfeel_matches_real_world() {
        let state = entries(&[
            ("decoration:blur:enabled", "true"),
            ("decoration:blur:passes", "1"),
            ("decoration:blur:size", "8"),
            ("decoration:rounding", "1"),
            ("decoration:shadow:enabled", "true"),
            ("decoration:shadow:range", "8"),
            ("decoration:shadow:render_power", "2"),
            ("general:gaps_in", "0"),
            ("general:gaps_out", "12"),
        ]);
        let expected = r#"-- Cloud Center user override file for lookandfeel configuration.
-- @cloud-center-state = {"decoration:blur:enabled": "true", "decoration:blur:passes": "1", "decoration:blur:size": "8", "decoration:rounding": "1", "decoration:shadow:enabled": "true", "decoration:shadow:range": "8", "decoration:shadow:render_power": "2", "general:gaps_in": "0", "general:gaps_out": "12"}

require("source.lookandfeel")

hl.config({
    general = {
        gaps_out = 12,
        gaps_in = 0,
    },
    decoration = {
        rounding = 1,
        shadow = {
            enabled = true,
            range = 8,
            render_power = 2,
        },
        blur = {
            enabled = true,
            passes = 1,
            size = 8,
        },
    },
})
"#;
        assert_eq!(render_surface(&state, "lookandfeel"), expected);
    }

    #[test]
    fn render_cursor_matches_real_world() {
        let state = entries(&[
            ("cursor:enable_hyprcursor", "true"),
            ("cursor:hide_on_key_press", "false"),
            ("cursor:hide_on_touch", "false"),
            ("cursor:hotspot_padding", "1"),
            ("cursor:inactive_timeout", "3"),
            ("cursor:no_warps", "true"),
            ("cursor:persistent_warps", "true"),
            ("cursor:warp_on_change_workspace", "1"),
            ("cursor:zoom_factor", "1"),
        ]);
        let expected = r#"-- Cloud Center user override file for cursor configuration.
-- @cloud-center-state = {"cursor:enable_hyprcursor": "true", "cursor:hide_on_key_press": "false", "cursor:hide_on_touch": "false", "cursor:hotspot_padding": "1", "cursor:inactive_timeout": "3", "cursor:no_warps": "true", "cursor:persistent_warps": "true", "cursor:warp_on_change_workspace": "1", "cursor:zoom_factor": "1"}

hl.config({
    cursor = {
        enable_hyprcursor = true,
        no_warps = true,
        persistent_warps = true,
        warp_on_change_workspace = 1,
        zoom_factor = 1,
        inactive_timeout = 3,
        hide_on_key_press = false,
        hide_on_touch = false,
        hotspot_padding = 1,
    },
})
"#;
        assert_eq!(render_surface(&state, "cursor"), expected);
    }

    #[test]
    fn render_animations_matches_real_world() {
        let state = entries(&[
            ("animations:animation", "windows,1,4,Bouncy"),
            ("animations:bezier", "Bouncy,0.531,-0.817,0.64,1.885"),
        ]);
        let expected = r#"-- Cloud Center user override file for animations configuration.
-- @cloud-center-state = {"animations:animation": "windows,1,4,Bouncy", "animations:bezier": "Bouncy,0.531,-0.817,0.64,1.885"}

require("source.animations")

hl.curve("Bouncy", { type = "bezier", points = { { 0.531, -0.817 }, { 0.64, 1.885 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "Bouncy" })
"#;
        assert_eq!(render_surface(&state, "animations"), expected);
    }

    // -- Animation parsing ----------------------------------------------------

    #[test]
    fn curve_parses_bouncy() {
        assert_eq!(
            render_curve("Bouncy,0.531,-0.817,0.64,1.885").unwrap(),
            "hl.curve(\"Bouncy\", { type = \"bezier\", points = { { 0.531, -0.817 }, { 0.64, 1.885 } } })"
        );
    }

    #[test]
    fn animation_parses_simple_form() {
        assert_eq!(
            render_animation("windows,1,4,Bouncy").unwrap(),
            "hl.animation({ leaf = \"windows\", enabled = true, speed = 4, bezier = \"Bouncy\" })"
        );
    }

    #[test]
    fn animation_with_style_appends_field() {
        assert_eq!(
            render_animation("windows,1,4,Bouncy,slide").unwrap(),
            "hl.animation({ leaf = \"windows\", enabled = true, speed = 4, bezier = \"Bouncy\", style = \"slide\" })"
        );
    }

    #[test]
    fn build_live_eval_nested_and_hyphenated_keys() {
        assert_eq!(
            build_live_eval("general:border_size", "3"),
            Some("hl.config({ general = { border_size = 3 } })".into()),
        );
        assert_eq!(
            build_live_eval("decoration:shadow:enabled", "true"),
            Some("hl.config({ decoration = { shadow = { enabled = true } } })".into()),
        );
        assert_eq!(
            build_live_eval("input:touchpad:tap-to-click", "true"),
            Some("hl.config({ input = { touchpad = { tap_to_click = true } } })".into()),
        );
    }
}
