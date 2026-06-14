//! hcm — Cloud Center's Hyprland config manager.
//!
//! Cloud Center shells out to this binary instead of reading and writing Lua
//! files directly. Replaces `hypr_persist_lua.py`, `hyprlua_runtime.py`, and
//! the non-GTK half of `hcm_lua.py`.
//!
//!   hcm set KEY VALUE        persist a key into the right user_*.lua
//!   hcm apply KEY VALUE      persist, then live-apply via hyprctl eval
//!   hcm reset-page PAGE      drop every key on that page from state
//!   hcm scan [--json]        list source/*.lua with status + description
//!   hcm activate SURFACE     load user_SURFACE.lua instead of the distro source
//!   hcm revert SURFACE       delete user_SURFACE.lua and restore the source
//!   hcm archive-legacy       one-shot move of pre-Lua *.conf into .legacy/
//!
//! Global flag `--hypr-dir PATH` overrides `$HOME/.config/hypr` (used by
//! tests). JSON payloads go to stdout; logs go to stderr.

mod persist;
mod runtime;
mod scan;

use std::path::PathBuf;
use std::process::ExitCode;

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};

use persist::HyprDirs;

#[derive(Parser, Debug)]
#[command(name = "hcm", about = "Cloud Center / Hyprland config manager", version)]
struct Cli {
    /// Override $HOME/.config/hypr.
    #[arg(long, global = true)]
    hypr_dir: Option<PathBuf>,

    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Persist a single key=value into the right user_*.lua file.
    Set { key: String, value: String },
    /// Persist a key, then apply it live (hyprctl eval, reload on failure).
    Apply { key: String, value: String },
    /// Drop every state key on the given page.
    ResetPage { page: String },
    /// List source/*.lua with distro/override status.
    Scan {
        /// Emit a JSON array on stdout (default: human-readable table).
        #[arg(long)]
        json: bool,
    },
    /// Make user_SURFACE.lua active, creating it from source if needed.
    Activate { surface: String },
    /// Delete user_SURFACE.lua and re-activate the distro source.
    Revert { surface: String },
    /// One-shot move of pre-Lua *.conf files into .legacy/.
    ArchiveLegacy,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let dirs = cli.hypr_dir.map(HyprDirs::new).unwrap_or_else(HyprDirs::current);

    let result = match cli.cmd {
        Cmd::Set { key, value } => persist::set(&dirs, &key, &value).and_then(emit_json),
        Cmd::Apply { key, value } => persist::apply(&dirs, &key, &value).and_then(emit_json),
        Cmd::ResetPage { page } => persist::reset_page(&dirs, &page).and_then(emit_json),
        Cmd::Scan { json } => show_scan(&dirs, json),
        Cmd::Activate { surface } => run_on_module(&dirs, &surface, scan::enable),
        Cmd::Revert { surface } => run_on_module(&dirs, &surface, scan::disable),
        Cmd::ArchiveLegacy => archive_legacy(&dirs),
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => { eprintln!("hcm: {e:#}"); ExitCode::FAILURE }
    }
}

fn show_scan(dirs: &HyprDirs, json: bool) -> Result<()> {
    let modules = scan::scan(dirs);
    if json {
        return emit_json(modules);
    }
    for m in &modules {
        let status = match m.status {
            scan::Status::Distro => "distro       ",
            scan::Status::UserOverride => "user-override",
        };
        println!("{:24}  {}  {}", m.filename, status, m.description);
    }
    Ok(())
}

/// Resolve `SURFACE` to its `source/SURFACE.lua` path and hand it off to
/// either `scan::enable` or `scan::disable`.
fn run_on_module<T, F>(dirs: &HyprDirs, surface: &str, op: F) -> Result<()>
where
    T: serde::Serialize,
    F: FnOnce(&HyprDirs, &std::path::Path) -> Result<T>,
{
    let source = dirs.source_dir().join(format!("{surface}.lua"));
    if !source.exists() {
        return Err(anyhow!("source module not found: {}", source.display()));
    }
    emit_json(op(dirs, &source)?)
}

fn archive_legacy(dirs: &HyprDirs) -> Result<()> {
    let n = runtime::archive_legacy(dirs).context("archive legacy .conf files")?;
    println!("{n}");
    Ok(())
}

fn emit_json<T: serde::Serialize>(value: T) -> Result<()> {
    let s = serde_json::to_string(&value).context("serialize JSON response")?;
    println!("{s}");
    Ok(())
}
