//! Inspect `source/*.lua` and flip individual modules between distro and
//! user-override. The non-GTK half of the old `hcm_lua.py`.

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use rayon::prelude::*;
use serde::Serialize;

use crate::persist::{atomic_write, HyprDirs};
use crate::runtime::{activate_source, activate_user, active_requires};

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Status {
    Distro,
    UserOverride,
}

#[derive(Debug, Clone, Serialize)]
pub struct Module {
    pub filename: String,
    pub path: PathBuf,
    pub description: String,
    pub status: Status,
}

#[derive(Debug, Clone, Serialize)]
pub struct Enabled {
    pub edit_path: PathBuf,
    pub activated: bool,
    pub message: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Disabled {
    pub ok: bool,
    pub message: String,
}

/// List every `source/*.lua` with its description and whether the user
/// override is currently live. Description parsing runs in parallel — every
/// file open is independent.
pub fn scan(dirs: &HyprDirs) -> Vec<Module> {
    let source_dir = dirs.source_dir();
    if !source_dir.is_dir() { return Vec::new(); }

    let main_text = fs::read_to_string(dirs.main_lua()).unwrap_or_default();
    let live = active_requires(&main_text);

    let mut files: Vec<PathBuf> = match fs::read_dir(&source_dir) {
        Ok(rd) => rd
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|ext| ext == "lua"))
            .collect(),
        Err(_) => return Vec::new(),
    };
    files.sort();

    files.par_iter()
        .map(|p| {
            let filename = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let stem = p.file_stem().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            let user_path = dirs.user_module_for(p);
            let user_line = format!("require(\"user-configs.user_{stem}\") -- managed by Cloud Center");
            let status = if user_path.exists() && live.contains(&user_line) {
                Status::UserOverride
            } else {
                Status::Distro
            };
            Module { filename, path: p.clone(), description: describe(p), status }
        })
        .collect()
}

/// First line of useful documentation in `path`: either `-- @description = ...`
/// or the first plain comment that isn't a separator.
fn describe(path: &Path) -> String {
    let Ok(text) = fs::read_to_string(path) else {
        return "No description available.".into();
    };
    let head: Vec<&str> = text.lines().take(10).collect();

    for line in &head {
        if let Some(after) = line.strip_prefix("--")
            .and_then(|r| r.trim_start().strip_prefix("@description"))
            .and_then(|r| r.trim_start().strip_prefix('='))
            .map(str::trim)
        {
            if !after.is_empty() { return after.into(); }
        }
    }
    for line in &head {
        if let Some(rest) = line.strip_prefix("--") {
            let trimmed = rest.trim();
            if !trimmed.is_empty() && !trimmed.starts_with('-') {
                return trimmed.into();
            }
        }
    }
    "No description available.".into()
}

/// Copy `source/SURFACE.lua` → `user-configs/user_SURFACE.lua` (if missing)
/// and flip the require line in `hyprland.lua`.
pub fn enable(dirs: &HyprDirs, source_file: &Path) -> Result<Enabled> {
    let stem = stem_of(source_file)?;
    let edit_path = dirs.user_module_for(source_file);
    let created = !edit_path.exists();
    if created {
        let body = fs::read(source_file)
            .with_context(|| format!("read {}", source_file.display()))?;
        atomic_write(&edit_path, &body)?;
    }

    let edit_name = file_name(&edit_path);
    let main_lua = dirs.main_lua();
    if !main_lua.exists() {
        let verb = if created { "Created" } else { "Saved" };
        return Ok(Enabled {
            edit_path,
            activated: false,
            message: format!("{verb} {edit_name}, but hyprland.lua is missing so it isn't loaded"),
        });
    }

    let text = fs::read_to_string(&main_lua).with_context(|| format!("read {}", main_lua.display()))?;
    atomic_write(&main_lua, activate_user(&text, &stem).as_bytes())?;

    Ok(Enabled {
        edit_path,
        activated: true,
        message: format!("Saved {edit_name} — user override activated"),
    })
}

/// Delete `user-configs/user_SURFACE.lua` and re-enable the distro source in
/// `hyprland.lua`.
pub fn disable(dirs: &HyprDirs, source_file: &Path) -> Result<Disabled> {
    let stem = stem_of(source_file)?;
    let user_path = dirs.user_module_for(source_file);
    if !user_path.exists() {
        return Ok(Disabled {
            ok: false,
            message: "No user override found — already using distro source".into(),
        });
    }

    fs::remove_file(&user_path).with_context(|| format!("delete {}", user_path.display()))?;

    let main_lua = dirs.main_lua();
    if !main_lua.exists() {
        return Ok(Disabled {
            ok: false,
            message: format!(
                "Deleted {} but hyprland.lua is missing, so distro source isn't reactivated",
                file_name(&user_path)
            ),
        });
    }

    let text = fs::read_to_string(&main_lua).with_context(|| format!("read {}", main_lua.display()))?;
    atomic_write(&main_lua, activate_source(&text, &stem).as_bytes())?;

    Ok(Disabled {
        ok: true,
        message: format!("Reverted {} to distro source", file_name(source_file)),
    })
}

fn stem_of(p: &Path) -> Result<String> {
    p.file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .ok_or_else(|| anyhow!("path has no stem: {}", p.display()))
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn describe_prefers_at_description_tag() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("x.lua");
        fs::write(&p, "-- @description = Demo module\n-- noise\n").unwrap();
        assert_eq!(describe(&p), "Demo module");
    }

    #[test]
    fn describe_falls_back_to_first_comment() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("x.lua");
        fs::write(&p, "-- Just a comment\nlocal a = 1\n").unwrap();
        assert_eq!(describe(&p), "Just a comment");
    }

    #[test]
    fn describe_default_when_missing() {
        let dir = tempdir().unwrap();
        let p = dir.path().join("x.lua");
        fs::write(&p, "local a = 1\n").unwrap();
        assert_eq!(describe(&p), "No description available.");
    }

    #[test]
    fn scan_marks_user_override_when_live() {
        let dir = tempdir().unwrap();
        let dirs = HyprDirs::new(dir.path());
        fs::create_dir_all(dirs.source_dir()).unwrap();
        fs::create_dir_all(dirs.user_dir()).unwrap();
        fs::write(dirs.source_dir().join("input.lua"), "-- Input module\n").unwrap();
        fs::write(dirs.user_dir().join("user_input.lua"), "-- override\n").unwrap();
        fs::write(
            dirs.main_lua(),
            "require(\"source.variables\")\n\
             require(\"user-configs.user_input\") -- managed by Cloud Center\n",
        ).unwrap();
        let files = scan(&dirs);
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].status, Status::UserOverride);
    }

    #[test]
    fn scan_marks_distro_when_no_user_file() {
        let dir = tempdir().unwrap();
        let dirs = HyprDirs::new(dir.path());
        fs::create_dir_all(dirs.source_dir()).unwrap();
        fs::create_dir_all(dirs.user_dir()).unwrap();
        fs::write(dirs.source_dir().join("input.lua"), "-- Input module\n").unwrap();
        fs::write(dirs.main_lua(), "require(\"source.input\")\n").unwrap();
        let files = scan(&dirs);
        assert_eq!(files.len(), 1);
        assert_eq!(files[0].status, Status::Distro);
    }
}
