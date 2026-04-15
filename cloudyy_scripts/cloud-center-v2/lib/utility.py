"""
Cloud Center — lib/utility.py
Shared utilities: logging, XDG paths, command execution, settings persistence.
"""
from __future__ import annotations

import logging
import os
import re
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from typing import Final, TypeVar, overload

log = logging.getLogger(__name__)

_T = TypeVar("_T")
_TILDE = re.compile(r"(?:^|(?<=\s))~(?=/|$|\s)")

# ── XDG paths ────────────────────────────────────────────────────────────────

def _xdg(env: str, fallback: str) -> Path:
    v = os.environ.get(env, "").strip()
    return Path(v) if v and Path(v).is_absolute() else Path.home() / fallback

XDG_CACHE:  Final[Path] = _xdg("XDG_CACHE_HOME",  ".cache")
XDG_CONFIG: Final[Path] = _xdg("XDG_CONFIG_HOME", ".config")

CACHE_DIR:    Final[Path] = XDG_CACHE  / "cloud-center"
SETTINGS_DIR: Final[Path] = XDG_CONFIG / "cloud-center" / "settings"


def setup_cache() -> None:
    """Point pycache to XDG cache dir (call before any imports)."""
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        sys.pycache_prefix = str(CACHE_DIR / "pycache")
    except OSError as e:
        log.warning("Could not set pycache location: %s", e)


# ── Dependency preflight ──────────────────────────────────────────────────────

_REQUIRED = ["python-gobject", "gtk4", "libadwaita", "python-yaml"]

def preflight_check() -> None:
    missing = [
        p for p in _REQUIRED
        if subprocess.run(["pacman", "-Q", p], capture_output=True).returncode != 0
    ]
    if not missing:
        return
    log.warning("Missing packages: %s", ", ".join(missing))
    print(f"[Cloud Center] Missing: {' '.join(missing)}")
    print(f"[Cloud Center] Run: sudo pacman -S {' '.join(missing)}")
    result = subprocess.run(["pkexec", "pacman", "-S", "--noconfirm"] + missing)
    if result.returncode != 0:
        sys.exit(1)
    os.execv(sys.executable, [sys.executable] + sys.argv)


# ── Command execution (GLib.spawn_async — no fork() lock issues) ─────────────

def execute_command(cmd: str, title: str = "", terminal: bool = False) -> bool:
    """Launch a command detached via GLib. Safe from GTK thread."""
    if not cmd.strip():
        return False

    expanded = os.path.expandvars(_TILDE.sub(str(Path.home()), cmd)).strip()

    if terminal:
        argv = ["kitty", "--", "bash", "-c", expanded]
    else:
        argv = ["bash", "-c", expanded]

    from gi.repository import GLib
    try:
        result = GLib.spawn_async(
            argv,
            flags=GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
        )
        # pygobject ≥ 3.42 returns (pid, stdin_fd, stdout_fd, stderr_fd).
        # Older versions returned (ok: bool, pid: int).
        # In both cases the first element is truthy on success (pid > 0 or ok=True).
        if isinstance(result, (list, tuple)):
            return bool(result[0])
        return bool(result)
    except Exception as e:
        log.error("spawn failed for %r: %s", cmd, e)
        return False


# ── Settings persistence (atomic write) ──────────────────────────────────────

def _safe_path(key: str) -> Path | None:
    if not key or "\0" in key:
        return None
    try:
        base = SETTINGS_DIR.resolve()
        target = (base / key).resolve()
        target.relative_to(base)
        return target
    except (ValueError, OSError):
        return None


def save_setting(key: str, value: bool | int | float | str) -> bool:
    target = _safe_path(key)
    if not target:
        return False
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=target.parent)
        with os.fdopen(fd, "w") as f:
            f.write(str(value))
            f.flush()
            os.fsync(f.fileno())
        Path(tmp).rename(target)
        return True
    except OSError as e:
        log.error("save_setting failed for %s: %s", key, e)
        return False


@overload
def load_setting(key: str, default: bool) -> bool: ...
@overload
def load_setting(key: str, default: int) -> int: ...
@overload
def load_setting(key: str, default: float) -> float: ...
@overload
def load_setting(key: str, default: str) -> str: ...
@overload
def load_setting(key: str, default: None = None) -> str | None: ...

def load_setting(key, default=None):
    target = _safe_path(key)
    if not target:
        return default
    try:
        raw = target.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, OSError):
        return default
    try:
        match default:
            case bool():  return raw.lower() in {"true", "yes", "1", "on"}
            case int():   return int(raw)
            case float(): return float(raw)
            case _:       return raw
    except ValueError:
        return default


# ── Toast helper (schedules on GTK main thread) ───────────────────────────────

def toast(overlay, message: str, timeout: int = 2) -> None:
    if overlay is None:
        return
    from gi.repository import Adw, GLib
    def _show():
        t = Adw.Toast.new(message)
        t.set_timeout(timeout)
        overlay.add_toast(t)
        return False
    GLib.idle_add(_show)


# ── System info ───────────────────────────────────────────────────────────────

def get_system_info(key: str) -> str:
    try:
        match key:
            case "kernel":
                return os.uname().release
            case "cpu":
                for line in Path("/proc/cpuinfo").read_text().splitlines():
                    if line.lower().startswith("model name"):
                        return line.partition(":")[2].strip().split(" @")[0]
            case "memory_total":
                for line in Path("/proc/meminfo").read_text().splitlines():
                    if line.startswith("MemTotal:"):
                        return f"{round(int(line.split()[1]) / 1_048_576, 1)} GB"
            case "memory_used":
                info = {}
                for line in Path("/proc/meminfo").read_text().splitlines():
                    if line.startswith(("MemTotal:", "MemAvailable:")):
                        k, _, v = line.partition(":")
                        info[k.strip()] = int(v.split()[0])
                if "MemTotal" in info and "MemAvailable" in info:
                    return f"{round((info['MemTotal'] - info['MemAvailable']) / 1_048_576, 1)} GB"
            case "gpu":
                r = subprocess.run(["lspci", "-mm"], capture_output=True, text=True, timeout=3)
                for line in r.stdout.splitlines():
                    if '"VGA compatible controller"' in line or '"3D controller"' in line:
                                fields = re.findall(r'"([^"]+)"', line)
                                # lspci -mm fields: class, vendor, device, [subsystem vendor], [subsystem device]
                                if len(fields) >= 3:
                                    vendor = fields[1].strip()
                                    device = fields[2].strip()
                                    sub_vendor = fields[3].strip() if len(fields) >= 4 else ""

                                    # Prefer friendly name in brackets: "GB203 [GeForce RTX 5070 Ti]" -> "GeForce RTX 5070 Ti"
                                    m = re.search(r"\[([^\]]+)\]", device)
                                    gpu_name = m.group(1).strip() if m else device

                                    manufacturer = sub_vendor or vendor
                                    return f"{gpu_name} ({manufacturer})".strip()
    except Exception:
        pass
    return "N/A"
