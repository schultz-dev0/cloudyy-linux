"""GTK-free recording settings, paths, and capture arg building for Cloud Center."""
from __future__ import annotations

import hashlib
import logging
import mimetypes
import os
import shlex
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

import lib.utility as utility

log = logging.getLogger(__name__)

SETTINGS_PREFIX = "recording"

DEFAULT_FPS = 60
DEFAULT_FILETYPE = "mp4"
DEFAULT_EDIT_COMMAND = "xdg-open"
DEFAULT_ISLAND_PREVIEW_MS = 7000

COMBINE_SINK_NAME = "cloudyy_recording_mix"
RECORDING_STATE_FILE = Path("/tmp/cloudyy-recording.state")
THUMB_CACHE_DIR = utility.CACHE_DIR / "recording-thumbs"

# Extension -> gallery kind. Also used to tell images apart from videos for
# thumbnailing/copy behavior.
GALLERY_KINDS: dict[str, str] = {
    ".png": "screenshot",
    ".jpg": "screenshot",
    ".jpeg": "screenshot",
    ".webp": "screenshot",
    ".mp4": "recording",
    ".mkv": "recording",
    ".webm": "recording",
    ".mov": "recording",
}

ALLOWED_ACTIONS = frozenset({
    "set_setting",
    "trigger_screenshot",
    "trigger_record_toggle",
    "open",
    "edit",
    "copy",
    "delete",
    "reveal",
    "ensure_thumb",
})

_BOOL_KEYS = frozenset({"rec_audio_mic", "rec_audio_desktop", "auto_copy"})
_INT_KEYS = frozenset({"rec_fps", "island_preview_ms"})
_STRING_KEYS = frozenset({
    "screenshots_dir",
    "recordings_dir",
    "rec_mic_device",
    "rec_desktop_device",
    "rec_codec",
    "rec_filetype",
    "rec_filename_pattern",
    "edit_command",
})
_ALL_KEYS = _BOOL_KEYS | _INT_KEYS | _STRING_KEYS


def _setting_key(name: str) -> str:
    return f"{SETTINGS_PREFIX}/{name}"


def _xdg_or_home(env_var: str, home_subdir: str) -> str:
    value = os.environ.get(env_var, "").strip()
    if value:
        return value
    home = os.environ.get("HOME", os.path.expanduser("~"))
    return os.path.join(home, home_subdir)


def default_screenshots_dir() -> str:
    return os.path.join(_xdg_or_home("XDG_PICTURES_DIR", "Pictures"), "Screenshots")


def default_recordings_dir() -> str:
    return os.path.join(_xdg_or_home("XDG_VIDEOS_DIR", "Videos"), "Captures")


def load_settings() -> dict[str, Any]:
    return {
        "screenshots_dir": utility.load_setting(
            _setting_key("screenshots_dir"), default_screenshots_dir(),
        ),
        "recordings_dir": utility.load_setting(
            _setting_key("recordings_dir"), default_recordings_dir(),
        ),
        "rec_audio_mic": utility.load_setting(_setting_key("rec_audio_mic"), False),
        "rec_audio_desktop": utility.load_setting(_setting_key("rec_audio_desktop"), False),
        "rec_mic_device": utility.load_setting(_setting_key("rec_mic_device"), ""),
        "rec_desktop_device": utility.load_setting(_setting_key("rec_desktop_device"), ""),
        "rec_fps": utility.load_setting(_setting_key("rec_fps"), DEFAULT_FPS),
        "rec_codec": utility.load_setting(_setting_key("rec_codec"), ""),
        "rec_filetype": utility.load_setting(_setting_key("rec_filetype"), DEFAULT_FILETYPE),
        "rec_filename_pattern": utility.load_setting(_setting_key("rec_filename_pattern"), ""),
        "island_preview_ms": utility.load_setting(
            _setting_key("island_preview_ms"), DEFAULT_ISLAND_PREVIEW_MS,
        ),
        "auto_copy": utility.load_setting(_setting_key("auto_copy"), False),
        "edit_command": utility.load_setting(_setting_key("edit_command"), DEFAULT_EDIT_COMMAND),
    }


def save_setting(key: str, value: Any) -> dict[str, Any]:
    if key not in _ALL_KEYS:
        return {"ok": False, "message": f"Unknown setting: {key}"}
    if key in _BOOL_KEYS and not isinstance(value, bool):
        return {"ok": False, "message": f"{key} must be a boolean"}
    if key in _INT_KEYS:
        try:
            value = int(value)
        except (TypeError, ValueError):
            return {"ok": False, "message": f"{key} must be an integer"}
    elif key in _STRING_KEYS:
        value = str(value)
    if utility.save_setting(_setting_key(key), value):
        return {"ok": True, "message": f"Saved {key}"}
    return {"ok": False, "message": f"Failed to save {key}"}


def expand_filename_pattern(pattern: str, *, now: datetime | None = None) -> str:
    dt = now or datetime.now()
    replacements = {
        "{date}": dt.strftime("%Y-%m-%d"),
        "{time}": dt.strftime("%H%M%S"),
        "{datetime}": dt.strftime("%Y-%m-%d-%H%M%S"),
    }
    result = pattern
    for token, expanded in replacements.items():
        result = result.replace(token, expanded)
    return result


def build_hyprcap_front_args(
    settings: dict[str, Any],
    *,
    kind: str,
    filename: str | None,
) -> list[str]:
    out_dir = (
        settings.get("screenshots_dir") or default_screenshots_dir()
        if kind == "shot"
        else settings.get("recordings_dir") or default_recordings_dir()
    )
    args = ["-w", "-o", str(out_dir)]
    if filename:
        args.extend(["-f", filename])
    filetype = str(settings.get("rec_filetype") or "").strip()
    if kind == "rec" and filetype:
        args.extend(["--filetype", filetype])
    if settings.get("auto_copy"):
        args.append("-c")
    return args


def build_wf_recorder_passthrough(
    settings: dict[str, Any],
    *,
    audio_source: str | None,
) -> list[str]:
    args: list[str] = []
    if audio_source:
        args.append(f"-a{audio_source}")
    fps = settings.get("rec_fps")
    if fps:
        args.extend(["-r", str(int(fps))])
    codec = str(settings.get("rec_codec") or "").strip()
    if codec:
        args.extend(["-c", codec])
    return args


def format_recording_args_shell(
    settings: dict[str, Any],
    *,
    kind: str,
    filename: str | None = None,
    audio_source: str | None = None,
) -> str:
    front = build_hyprcap_front_args(settings, kind=kind, filename=filename)
    if kind != "rec":
        return " ".join(shlex.quote(arg) for arg in front)
    passthrough = build_wf_recorder_passthrough(settings, audio_source=audio_source)
    parts = front + (["--"] + passthrough if passthrough else [])
    return " ".join(shlex.quote(arg) for arg in parts)


# ── Audio inputs ──────────────────────────────────────────────────────────────

def list_audio_inputs() -> dict[str, list[dict[str, Any]]]:
    from lib import audio_core

    mics = [
        {"name": source.name, "description": source.description, "is_default": source.is_default}
        for source in audio_core.list_sources()
    ]
    desktops = [
        {
            "name": f"{sink.name}.monitor",
            "description": sink.description,
            "is_default": sink.is_default,
        }
        for sink in audio_core.list_sinks()
    ]
    return {"mics": mics, "desktops": desktops}


def _pick_device(devices: list[dict[str, Any]], named: str) -> str:
    if named:
        return named
    for device in devices:
        if device.get("is_default"):
            return str(device["name"])
    return str(devices[0]["name"]) if devices else ""


def resolve_audio_source(settings: dict[str, Any]) -> dict[str, Any]:
    use_mic = bool(settings.get("rec_audio_mic"))
    use_desktop = bool(settings.get("rec_audio_desktop"))
    if not use_mic and not use_desktop:
        return {"ok": True, "source": None, "message": ""}

    inputs = list_audio_inputs()
    mic = _pick_device(inputs["mics"], str(settings.get("rec_mic_device") or ""))
    desktop = _pick_device(inputs["desktops"], str(settings.get("rec_desktop_device") or ""))

    if use_mic and not use_desktop:
        if not mic:
            return {"ok": False, "source": None, "message": "No microphone available"}
        return {"ok": True, "source": mic, "message": ""}

    if use_desktop and not use_mic:
        if not desktop:
            return {"ok": False, "source": None, "message": "No desktop audio available"}
        return {"ok": True, "source": desktop, "message": ""}

    if not mic or not desktop:
        return {"ok": False, "source": None, "message": "Mic and desktop audio are both required for a combine mix"}
    combined = ensure_combine_source(mic, desktop)
    if not combined.get("ok"):
        return {"ok": False, "source": None, "message": combined.get("message", "Combine setup failed")}
    return {"ok": True, "source": combined.get("source"), "message": ""}


# ── PipeWire combine mix ──────────────────────────────────────────────────────

def _pactl_run(args: list[str], timeout: int = 8) -> tuple[bool, str]:
    try:
        result = subprocess.run(["pactl"] + args, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, ((result.stdout or "") + (result.stderr or "")).strip()
    except Exception as exc:
        return False, str(exc)


def _sink_exists(name: str) -> bool:
    ok, out = _pactl_run(["list", "sinks", "short"])
    if not ok:
        return False
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) >= 2 and fields[1] == name:
            return True
    return False


def _loopback_module_ids_for_sink(sink_name: str) -> tuple[bool, list[str]]:
    ok, out = _pactl_run(["list", "modules", "short"])
    if not ok:
        return False, []
    ids: list[str] = []
    target = f"sink={sink_name}"
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) >= 3 and fields[1] == "module-loopback" and target in fields[2].split():
            ids.append(fields[0])
    return True, ids


def ensure_combine_source(mic: str, desktop_monitor: str) -> dict[str, Any]:
    """Idempotently (re)build the mic+desktop combine sink; never partially fall back."""
    if not mic or not desktop_monitor:
        return {"ok": False, "source": "", "message": "Both a microphone and desktop source are required"}

    if not _sink_exists(COMBINE_SINK_NAME):
        ok, out = _pactl_run([
            "load-module", "module-null-sink",
            f"sink_name={COMBINE_SINK_NAME}",
            "sink_properties=device.description=CloudyyRecordingMix",
        ])
        if not ok:
            return {"ok": False, "source": "", "message": f"Failed to create combine sink: {out}"}

    listed_ok, stale_module_ids = _loopback_module_ids_for_sink(COMBINE_SINK_NAME)
    if not listed_ok:
        return {"ok": False, "source": "", "message": "Failed to list existing loopback modules"}

    for module_id in stale_module_ids:
        unloaded, out = _pactl_run(["unload-module", module_id])
        if not unloaded:
            return {
                "ok": False, "source": "",
                "message": f"Failed to unload stale loopback module {module_id}: {out}",
            }

    for source in (mic, desktop_monitor):
        ok, out = _pactl_run([
            "load-module", "module-loopback", f"source={source}", f"sink={COMBINE_SINK_NAME}",
        ])
        if not ok:
            return {"ok": False, "source": "", "message": f"Failed to link {source} into combine mix: {out}"}

    return {"ok": True, "source": f"{COMBINE_SINK_NAME}.monitor", "message": ""}


# ── Gallery ───────────────────────────────────────────────────────────────────

def thumb_path_for(path: str, mtime_ms: int) -> Path:
    digest = hashlib.sha1(f"{path}|{mtime_ms}".encode("utf-8")).hexdigest()
    return THUMB_CACHE_DIR / f"{digest}.jpg"


def list_gallery(settings: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    seen_dirs: set[str] = set()
    for directory in (settings.get("screenshots_dir"), settings.get("recordings_dir")):
        if not directory:
            continue
        base = Path(directory)
        if not base.is_dir():
            continue
        resolved = str(base.resolve())
        if resolved in seen_dirs:
            continue
        seen_dirs.add(resolved)
        for entry in base.iterdir():
            kind = GALLERY_KINDS.get(entry.suffix.lower())
            if kind is None or not entry.is_file():
                continue
            try:
                stat = entry.stat()
            except OSError as exc:
                log.warning("Failed to stat gallery entry %s: %s", entry, exc)
                continue
            mtime_ms = int(stat.st_mtime * 1000)
            thumb = thumb_path_for(str(entry), mtime_ms)
            items.append({
                "path": str(entry),
                "kind": kind,
                "mtime_ms": mtime_ms,
                "size_bytes": stat.st_size,
                "thumb_path": str(thumb) if thumb.exists() else "",
            })
    items.sort(key=lambda item: item["mtime_ms"], reverse=True)
    return items


def ensure_thumb(path: str) -> dict[str, Any]:
    source = Path(path)
    try:
        mtime_ms = int(source.stat().st_mtime * 1000)
    except OSError as exc:
        return {"ok": False, "thumb_path": "", "message": str(exc)}

    thumb = thumb_path_for(path, mtime_ms)
    if thumb.exists():
        return {"ok": True, "thumb_path": str(thumb), "message": ""}

    thumb.parent.mkdir(parents=True, exist_ok=True)
    kind = GALLERY_KINDS.get(source.suffix.lower())
    if kind == "screenshot":
        try:
            shutil.copyfile(source, thumb)
        except OSError as exc:
            return {"ok": False, "thumb_path": "", "message": str(exc)}
        return {"ok": True, "thumb_path": str(thumb), "message": ""}

    if not shutil.which("ffmpeg"):
        return {"ok": False, "thumb_path": "", "message": "ffmpeg not found"}
    try:
        result = subprocess.run(
            ["ffmpeg", "-y", "-i", str(source), "-frames:v", "1", "-q:v", "3", str(thumb)],
            capture_output=True, text=True, timeout=20,
        )
    except Exception as exc:
        thumb.unlink(missing_ok=True)
        return {"ok": False, "thumb_path": "", "message": str(exc)}
    if result.returncode != 0 or not thumb.exists():
        thumb.unlink(missing_ok=True)
        return {"ok": False, "thumb_path": "", "message": (result.stderr or "ffmpeg failed").strip()}
    return {"ok": True, "thumb_path": str(thumb), "message": ""}


# ── File actions ──────────────────────────────────────────────────────────────

def _open_argv(path: Path) -> list[str]:
    # On Hyprland, xdg-open often resolves images to a browser (Chrome desktop
    # files claim image/*) while gio uses the GLib default (Loupe/mpv here).
    if shutil.which("gio"):
        return ["gio", "open", str(path)]
    return ["xdg-open", str(path)]


def _reveal_argv(path: Path) -> list[str]:
    """Open the containing folder in a real file manager (not kitty/xdg-open)."""
    parent = str(path.parent)
    # Prefer an explicit session override when present.
    fm = (os.environ.get("FILE_MANAGER") or "").strip()
    if fm:
        return shlex.split(fm) + [parent]
    # Distro default FM is Nautilus; --select highlights the file.
    if shutil.which("nautilus"):
        return ["nautilus", "--select", str(path)]
    if shutil.which("gio"):
        return ["gio", "open", parent]
    return ["xdg-open", parent]


def _spawn(argv: list[str], success_message: str) -> dict[str, Any]:
    try:
        subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return {"ok": True, "message": success_message}
    except OSError as exc:
        return {"ok": False, "message": str(exc)}


def _copy_to_clipboard(path: Path) -> dict[str, Any]:
    if not shutil.which("wl-copy"):
        return {"ok": False, "message": "wl-copy not found"}
    kind = GALLERY_KINDS.get(path.suffix.lower())
    try:
        if kind == "screenshot":
            mime = mimetypes.guess_type(str(path))[0] or "image/png"
            with open(path, "rb") as handle:
                result = subprocess.run(["wl-copy", "--type", mime], stdin=handle, timeout=10)
        else:
            uri = path.resolve().as_uri()
            result = subprocess.run(
                ["wl-copy", "--type", "text/uri-list"],
                input=f"{uri}\r\n", text=True, timeout=10,
            )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "message": str(exc)}
    if result.returncode != 0:
        return {"ok": False, "message": "wl-copy failed"}
    return {"ok": True, "message": f"Copied {path.name}"}


def _delete_gallery_file(path: Path) -> dict[str, Any]:
    try:
        mtime_ms = int(path.stat().st_mtime * 1000)
    except OSError:
        mtime_ms = None
    try:
        path.unlink()
    except FileNotFoundError:
        return {"ok": False, "message": "File not found"}
    except OSError as exc:
        return {"ok": False, "message": str(exc)}
    if mtime_ms is not None:
        try:
            thumb_path_for(str(path), mtime_ms).unlink(missing_ok=True)
        except OSError as exc:
            log.warning("Failed to remove thumbnail for %s: %s", path, exc)
    return {"ok": True, "message": f"Deleted {path.name}"}


def run_file_action(action: str, path: str, *, edit_command: str) -> dict[str, Any]:
    file_path = Path(path)
    if action == "open":
        return _spawn(_open_argv(file_path), f"Opened {file_path.name}")
    if action == "edit":
        command = edit_command.strip() or DEFAULT_EDIT_COMMAND
        # Bare xdg-open / empty → same opener as "open" (avoid browser MIME traps).
        if command in ("", "xdg-open"):
            return _spawn(_open_argv(file_path), f"Editing {file_path.name}")
        return _spawn(shlex.split(command) + [str(file_path)], f"Editing {file_path.name}")
    if action == "reveal":
        return _spawn(_reveal_argv(file_path), f"Revealed {file_path.name}")
    if action == "copy":
        return _copy_to_clipboard(file_path)
    if action == "delete":
        return _delete_gallery_file(file_path)
    raise ValueError(f"unknown recording file action: {action}")


# ── Snapshot ──────────────────────────────────────────────────────────────────

def _parse_recording_state(state_file: Path = RECORDING_STATE_FILE) -> dict[str, Any]:
    try:
        content = state_file.read_text(encoding="utf-8")
    except OSError:
        return {"active": False, "out_file": "", "selection": ""}
    values: dict[str, str] = {}
    for line in content.splitlines():
        key, _, value = line.partition("=")
        if key:
            values[key.strip()] = value.strip()
    return {
        "active": values.get("RECORDING") == "1",
        "out_file": values.get("OUT_FILE", ""),
        "selection": values.get("SELECTION", ""),
    }


def build_recording_snapshot() -> dict[str, Any]:
    settings = load_settings()
    return {
        "revision": 0,
        "settings": settings,
        "audio_inputs": list_audio_inputs(),
        "recording": _parse_recording_state(RECORDING_STATE_FILE),
        "gallery": list_gallery(settings),
        "stale": False,
        "error": "",
    }
