//! `hyprland.lua` line transforms and one-shot legacy `.conf` archival.
//!
//! Two stateless concerns that both live next to the same source/ and
//! user-configs/ tree, so they're together. Replaces `hyprlua_runtime.py`.

use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::Path;

use crate::persist::HyprDirs;

// ── hyprland.lua require-line transforms ────────────────────────────────────
//
// The two `activate_*` functions are inverses: one makes the user override the
// live require line, the other restores the distro source. Matching tolerates
// trailing comments on the same line so real-world hyprland.lua edits still
// activate correctly.

/// Parse a `require("…")` line into `(commented, code)` when recognizable.
fn require_target(line: &str) -> Option<(bool, String)> {
    let raw = line.trim();
    let commented = raw.starts_with("--");
    let body = if commented {
        raw.strip_prefix("--").map(str::trim)?
    } else {
        raw
    };
    let code = body.split("--").next()?.trim();
    if code.starts_with("require(\"") {
        Some((commented, code.to_string()))
    } else {
        None
    }
}

/// Flip `hyprland.lua` so it loads `user-configs/user_SURFACE.lua` instead of
/// `source/SURFACE.lua`.
pub fn activate_user(text: &str, surface: &str) -> String {
    let source_on = format!("require(\"source.{surface}\")");
    let source_off = format!("-- {source_on}");
    let user_on = format!("require(\"user-configs.user_{surface}\") -- managed by Cloud Center");
    let user_code = format!("require(\"user-configs.user_{surface}\")");

    let mut out: Vec<String> = Vec::new();
    let mut seen_user = false;

    for line in text.split('\n') {
        match require_target(line) {
            Some((false, code)) if code == source_on => out.push(source_off.clone()),
            Some((_, code)) if code == user_code => {
                if !seen_user {
                    out.push(user_on.clone());
                    seen_user = true;
                }
            }
            _ => out.push(line.to_string()),
        }
    }

    let mut result = out.join("\n");
    if !seen_user {
        if !result.ends_with('\n') { result.push('\n'); }
        result.push_str(&user_on);
        result.push('\n');
    } else if !result.ends_with('\n') {
        result.push('\n');
    }
    result
}

/// Inverse of `activate_user`: re-enable `source/SURFACE.lua` and comment out
/// the user override line if one exists.
pub fn activate_source(text: &str, surface: &str) -> String {
    let source_on = format!("require(\"source.{surface}\")");
    let user_on = format!("require(\"user-configs.user_{surface}\") -- managed by Cloud Center");
    let user_code = format!("require(\"user-configs.user_{surface}\")");
    let user_off = format!("-- {user_on}");

    let mut out: Vec<String> = Vec::new();
    let mut seen_user = false;

    for line in text.split('\n') {
        match require_target(line) {
            Some((true, code)) if code == source_on => out.push(source_on.clone()),
            Some((_, code)) if code == user_code => {
                if !seen_user {
                    out.push(user_off.clone());
                    seen_user = true;
                }
            }
            _ => out.push(line.to_string()),
        }
    }

    let mut result = out.join("\n");
    if !result.is_empty() && !result.ends_with('\n') {
        result.push('\n');
    }
    result
}

/// Whitespace-normalized set of `require("...")` lines that are currently
/// uncommented. Used by `scan` to decide whether a user override is live.
pub fn active_requires(text: &str) -> HashSet<String> {
    text.lines()
        .filter_map(|line| {
            let (commented, code) = require_target(line)?;
            if commented { return None; }
            let marker = line.trim().split_once("--").map(|(_, c)| c.trim());
            match marker {
                Some(comment) if !comment.is_empty() => {
                    Some(format!("{} -- {}", squeeze(&code), squeeze(comment)))
                }
                _ => Some(squeeze(&code)),
            }
        })
        .collect()
}

fn squeeze(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

// ── Legacy .conf archival ───────────────────────────────────────────────────
//
// One-shot migration that moves pre-Lua `*.conf` files under `<hypr>/.legacy/`.
// A `.archived` sentinel records that the move ran so re-invoking is a no-op.

const ARCHIVE_SENTINEL: &str = ".archived";
const KEEP_AS_SIDECAR: &[&str] = &["hypridle.conf", "hyprlock.conf", "xdph.conf"];

pub fn archive_legacy(dirs: &HyprDirs) -> io::Result<u32> {
    let legacy = dirs.root().join(".legacy");
    let sentinel = legacy.join(ARCHIVE_SENTINEL);
    if sentinel.exists() {
        eprintln!("[hypr_persist] legacy conf archive already complete, skipping");
        return Ok(0);
    }
    fs::create_dir_all(&legacy)?;

    let mut moved = sweep(dirs.root(), &legacy)?;
    for sub in ["source", "user-configs"] {
        let from = dirs.root().join(sub);
        if !from.exists() { continue; }
        let to = legacy.join(sub);
        fs::create_dir_all(&to)?;
        moved += sweep(&from, &to)?;
    }

    fs::write(&sentinel, b"")?;
    eprintln!("[hypr_persist] archived {moved} legacy .conf file(s) -> {}", legacy.display());
    Ok(moved)
}

fn sweep(from: &Path, to: &Path) -> io::Result<u32> {
    let mut count = 0;
    let Ok(entries) = fs::read_dir(from) else { return Ok(0) };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|ext| ext != "conf") { continue; }
        let Some(name) = path.file_name().map(|n| n.to_string_lossy().into_owned()) else {
            continue;
        };
        if KEEP_AS_SIDECAR.contains(&name.as_str()) { continue; }
        fs::rename(&path, to.join(&name))?;
        count += 1;
    }
    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    // -- Activation -------------------------------------------------------

    fn count(text: &str, needle: &str) -> usize {
        text.matches(needle).count()
    }

    #[test]
    fn user_matches_require_with_trailing_comment() {
        let input = "require(\"source.lookandfeel\") -- distro default\n";
        let out = activate_user(input, "lookandfeel");
        assert!(out.contains("-- require(\"source.lookandfeel\")"));
        assert!(out.contains("require(\"user-configs.user_lookandfeel\") -- managed by Cloud Center"));
    }

    #[test]
    fn user_appends_when_absent() {
        let out = activate_user("require(\"source.lookandfeel\")\n", "lookandfeel");
        assert!(out.contains("-- require(\"source.lookandfeel\")"));
        assert!(out.contains("require(\"user-configs.user_lookandfeel\") -- managed by Cloud Center"));
        assert!(out.ends_with('\n'));
    }

    #[test]
    fn user_is_idempotent() {
        let once = activate_user("require(\"source.lookandfeel\")\n", "lookandfeel");
        let twice = activate_user(&once, "lookandfeel");
        assert_eq!(once, twice);
    }

    #[test]
    fn source_is_idempotent() {
        let input = "-- require(\"source.lookandfeel\")\n\
                     require(\"user-configs.user_lookandfeel\") -- managed by Cloud Center\n";
        let once = activate_source(input, "lookandfeel");
        let twice = activate_source(&once, "lookandfeel");
        assert_eq!(once, twice);
    }

    #[test]
    fn round_trip_is_a_fixed_point() {
        let input = "require(\"source.lookandfeel\")\n";
        let user = activate_user(input, "lookandfeel");
        let back = activate_source(&user, "lookandfeel");
        let user_again = activate_user(&back, "lookandfeel");
        assert_eq!(user, user_again);
    }

    #[test]
    fn dedupes_duplicate_user_lines() {
        let input = "require(\"user-configs.user_input\") -- managed by Cloud Center\n\
                     require(\"user-configs.user_input\") -- managed by Cloud Center\n";
        let out = activate_user(input, "input");
        assert_eq!(count(&out, "user-configs.user_input"), 1);
    }

    #[test]
    fn active_requires_skips_commented_lines() {
        let text = "require(\"source.variables\")\n\
                    -- require(\"source.lookandfeel\")\n\
                    require(\"user-configs.user_input\") -- managed by Cloud Center\n";
        let active = active_requires(text);
        assert!(active.contains("require(\"source.variables\")"));
        assert!(active.contains("require(\"user-configs.user_input\") -- managed by Cloud Center"));
        assert!(!active.iter().any(|l| l.contains("source.lookandfeel")));
    }

    #[test]
    fn real_hyprland_lua_round_trips_cleanly() {
        // Snapshot from the user's actual ~/.config/hypr/hyprland.lua.
        let input = "require(\"source.variables\")\n\
                     -- require(\"source.monitors\")\n\
                     -- require(\"source.lookandfeel\")\n\
                     require(\"source.autostart\")\n\
                     require(\"user-configs.user_lookandfeel\") -- managed by Cloud Center\n\
                     require(\"user-configs.user_animations\") -- managed by Cloud Center\n";
        assert_eq!(activate_user(input, "lookandfeel"), input);
    }

    // -- Legacy archive ---------------------------------------------------

    #[test]
    fn archive_keeps_sidecars() {
        let tmp = tempdir().unwrap();
        let dirs = HyprDirs::new(tmp.path());
        for f in ["hypridle.conf", "hyprlock.conf", "xdph.conf", "old.conf"] {
            fs::write(tmp.path().join(f), b"x").unwrap();
        }
        assert_eq!(archive_legacy(&dirs).unwrap(), 1);
        for f in ["hypridle.conf", "hyprlock.conf", "xdph.conf"] {
            assert!(tmp.path().join(f).exists());
        }
        assert!(tmp.path().join(".legacy/old.conf").exists());
    }

    #[test]
    fn archive_walks_nested_dirs() {
        let tmp = tempdir().unwrap();
        let dirs = HyprDirs::new(tmp.path());
        fs::create_dir_all(dirs.source_dir()).unwrap();
        fs::create_dir_all(dirs.user_dir()).unwrap();
        fs::write(dirs.source_dir().join("bindings.conf"), b"x").unwrap();
        fs::write(dirs.user_dir().join("user_input.conf"), b"y").unwrap();
        assert_eq!(archive_legacy(&dirs).unwrap(), 2);
        assert!(tmp.path().join(".legacy/source/bindings.conf").exists());
        assert!(tmp.path().join(".legacy/user-configs/user_input.conf").exists());
    }

    #[test]
    fn archive_is_idempotent() {
        let tmp = tempdir().unwrap();
        let dirs = HyprDirs::new(tmp.path());
        fs::create_dir_all(tmp.path().join(".legacy")).unwrap();
        fs::write(tmp.path().join(".legacy/.archived"), b"").unwrap();
        fs::write(tmp.path().join("old.conf"), b"x").unwrap();
        assert_eq!(archive_legacy(&dirs).unwrap(), 0);
        assert!(tmp.path().join("old.conf").exists());
    }
}
