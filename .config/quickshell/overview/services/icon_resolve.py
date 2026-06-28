#!/usr/bin/env python3
"""Freedesktop icon resolution shared by Quickshell modules (GTK icon theme + fallback)."""

from __future__ import annotations

import configparser
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
FIELD_RE = re.compile(r"^([A-Za-z0-9-]+)=(.*)$")
SECTION_RE = re.compile(r"^\[([^\]]+)\]$")
DESKTOP_DIRS = (HOME / ".local/share/applications", Path("/usr/share/applications"))
INDEX_VERSION = "gtk-v3"
STANDARD_APP_DIRS = (
    "scalable/apps",
    "512x512/apps",
    "256x256/apps",
    "128x128/apps",
    "96x96/apps",
    "64x64/apps",
    "48x48/apps",
    "32x32/apps",
    "24x24/apps",
    "22x22/apps",
    "16x16/apps",
)
GENERIC_ICONS = frozenset(
    {
        "",
        "application-x-executable",
        "application-default-icon",
        "unknown",
    }
)

ICON_ALIASES: dict[str, str] = {
    "xfce-filemanager": "org.xfce.thunar",
    "thunar": "org.xfce.thunar",
    "cursor": "co.anysphere.cursor",
    "zen": "zen-browser",
    "zen-bin": "zen-browser",
    "vesktop": "dev.vencord.Vesktop",
    "dev.vencord.vesktop": "dev.vencord.Vesktop",
    "dev.zed.zed": "dev.zed.Zed",
    "zeditor": "dev.zed.Zed",
    "steam-native": "steam",
    "steam-launcher": "steam",
    "steam-icon": "steam",
    "md.obsidian.obsidian": "obsidian",
    "appimagekit-obsidian": "obsidian",
    "org.cloudyy.cloudcenter": "cloud-center",
}


def normalize_icon_name(name: str) -> str:
    value = f"{name or ''}".strip()
    if value.startswith("image://icon/"):
        value = value[len("image://icon/") :]
    return value.split("?")[0].strip()


def icon_file_stem(name: str) -> str:
    normalized = normalize_icon_name(name)
    if not normalized:
        return ""
    if normalized.startswith("/"):
        return Path(normalized).stem
    lower = normalized.lower()
    for ext in (".svg", ".png", ".xpm", ".ico", ".jpg", ".jpeg"):
        if lower.endswith(ext):
            return normalized[: -len(ext)]
    return normalized


def alias_names(name: str) -> list[str]:
    normalized = normalize_icon_name(name)
    if not normalized:
        return []
    names = [normalized]
    alias = ICON_ALIASES.get(normalized)
    if alias and alias not in names:
        names.append(alias)
    steam_app = re.match(r"^steam_app_(\d+)$", normalized, re.IGNORECASE)
    if steam_app:
        icon_name = f"steam_icon_{steam_app.group(1)}"
        if icon_name not in names:
            names.append(icon_name)
    if normalized.lower().endswith("cloudcenter") and "cloud-center" not in names:
        names.append("cloud-center")
    return names


def get_icon_theme() -> str:
    settings = HOME / ".config/gtk-3.0/settings.ini"
    if settings.is_file():
        parser = configparser.ConfigParser()
        try:
            parser.read(settings, encoding="utf-8")
            theme = parser.get("Settings", "gtk-icon-theme-name", fallback="").strip()
            if theme:
                return theme
        except (configparser.Error, OSError):
            pass

    try:
        out = subprocess.check_output(
            ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip().strip("'")
        if out:
            return out
    except (subprocess.CalledProcessError, OSError):
        pass

    return "Fluent-green"


def theme_search_roots() -> list[Path]:
    theme = get_icon_theme()
    names = [theme, "hicolor", "cloudyy-apps", "Fluent-green", "Fluent", "Adwaita", "Papirus-Dark", "Papirus"]
    roots = [
        HOME / ".local/share/icons",
        HOME / ".icons",
        Path("/usr/share/icons"),
        HOME / ".local/share/pixmaps",
        Path("/usr/share/pixmaps"),
    ]
    dirs: list[Path] = []
    seen: set[Path] = set()
    for name in names:
        for root in roots[:3]:
            path = root / name
            if path.is_dir() and path not in seen:
                seen.add(path)
                dirs.append(path)
    for root in roots:
        if root.is_dir() and root not in seen:
            seen.add(root)
            dirs.append(root)
    return dirs


def _gtk_lookup(name: str, size: int = 48) -> str:
    os.environ.setdefault("DISPLAY", ":0")
    try:
        import gi

        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk

        if not Gtk.is_initialized():
            Gtk.init([])
        theme = Gtk.IconTheme.get_default()
        for lookup_size in (size, 128, 64, 48, 32, 256):
            info = theme.lookup_icon(name, lookup_size, Gtk.IconLookupFlags.USE_BUILTIN)
            if info:
                path = info.get_filename()
                if path and Path(path).is_file():
                    return path
    except Exception:
        pass
    return ""


def _match_icon_file(folder: Path, stem: str) -> str:
    if not folder.is_dir():
        return ""
    stem_lower = stem.lower()
    for ext in (".svg", ".png", ".xpm", ".ico"):
        exact = folder / f"{stem}{ext}"
        if exact.is_file():
            return str(exact)
        lower = folder / f"{stem_lower}{ext}"
        if lower.is_file():
            return str(lower)
    try:
        for entry in folder.iterdir():
            if not entry.is_file():
                continue
            if entry.stem.lower() != stem_lower:
                continue
            if entry.suffix.lower() in {".svg", ".png", ".xpm", ".ico"}:
                return str(entry)
    except OSError:
        pass
    return ""


def _filesystem_lookup(name: str) -> str:
    normalized = normalize_icon_name(name)
    if not normalized:
        return ""

    if normalized.startswith("/") and Path(normalized).is_file():
        return normalized
    if normalized.startswith("~/"):
        expanded = HOME / normalized[2:]
        if expanded.is_file():
            return str(expanded)

    stem = icon_file_stem(normalized)
    if not stem:
        return ""

    for base in theme_search_roots():
        for sub in STANDARD_APP_DIRS:
            hit = _match_icon_file(base / sub, stem)
            if hit:
                return hit

    home = HOME
    for ext in ("svg", "png"):
        custom = home / ".local/share/icons/cloudyy-apps" / f"{stem}.{ext}"
        if custom.is_file():
            return str(custom)
        pixmap = home / ".local/share/pixmaps" / f"{stem}.{ext}"
        if pixmap.is_file():
            return str(pixmap)
        for folder in (home / ".local/share/icons/cloudyy-apps", home / ".local/share/pixmaps"):
            hit = _match_icon_file(folder, stem)
            if hit:
                return hit

    if stem.lower().startswith("steam_icon_"):
        for base in (
            home / ".local/share/Steam/steam/games",
            home / ".steam/debian-installation/steam/games",
            home / ".steam/steam/games",
        ):
            hit = _match_icon_file(base, stem)
            if hit:
                return hit

    return ""


def lookup_icon(name: str, size: int = 48) -> str:
    for candidate in alias_names(name):
        path = _gtk_lookup(candidate, size)
        if path:
            return path
        path = _filesystem_lookup(candidate)
        if path:
            return path
    return ""


def resolve_app_icon(
    icon: str = "",
    desktop_id: str = "",
    wmclass: str = "",
    exec_cmd: str = "",
    size: int = 48,
) -> str:
    primary = normalize_icon_name(icon)
    for candidate in [primary, normalize_icon_name(desktop_id)]:
        if not candidate:
            continue
        path = lookup_icon(candidate, size)
        if path:
            return path

    if primary in GENERIC_ICONS:
        for candidate in [normalize_icon_name(wmclass)]:
            if not candidate:
                continue
            path = lookup_icon(candidate, size)
            if path:
                return path
        if exec_cmd:
            exec_base = Path(exec_cmd.split()[0]).name
            path = lookup_icon(exec_base, size)
            if path:
                return path

    return ""


def read_desktop(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    in_entry = False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return fields
    for line in text.splitlines():
        section_match = SECTION_RE.match(line.strip())
        if section_match:
            in_entry = section_match.group(1) == "Desktop Entry"
            continue
        if not in_entry:
            continue
        match = FIELD_RE.match(line)
        if match:
            fields[match.group(1)] = match.group(2).strip()
    return fields


def iter_desktop_entries() -> list[tuple[Path, dict[str, str]]]:
    entries: list[tuple[Path, dict[str, str]]] = []
    seen: set[str] = set()
    for folder in DESKTOP_DIRS:
        if not folder.is_dir():
            continue
        try:
            desktops = sorted(folder.glob("*.desktop"))
        except OSError:
            continue
        for path in desktops:
            app_id = path.stem
            if app_id in seen:
                continue
            seen.add(app_id)
            fields = read_desktop(path)
            if fields.get("NoDisplay") == "true" or fields.get("Hidden") == "true":
                continue
            if not fields.get("Name") or not fields.get("Exec"):
                continue
            entries.append((path, fields))
    return entries


CHROME_WAYLAND_DESKTOP_RE = re.compile(
    r"^(?P<browser>chrome|chromium|msedge)-(?P<appid>[a-z0-9]+)-(?P<profile>.+)$",
    re.I,
)
CHROME_WAYLAND_WMCLASS_RE = re.compile(
    r"^(?P<browser>chrome|chromium|msedge)-(?P<appid>[a-z0-9]+)-(?P<profile>.+)$",
    re.I,
)
CRX_WMCLASS_RE = re.compile(r"^crx?_+(?P<appid>[a-z0-9]+)$", re.I)
PROFILE_DIR_RE = re.compile(
    r'--profile-directory=(?:\"([^\"]+)\"|\'([^\']+)\'|(Default|Profile\s+\d+))',
    re.I,
)


def profile_suffix_from_exec(exec_cmd: str) -> str:
    match = PROFILE_DIR_RE.search(exec_cmd)
    if not match:
        return "Default"
    profile = match.group(1) or match.group(2) or match.group(3)
    if profile == "Default":
        return "Default"
    return profile.replace(" ", "_")


def browser_prefix_from_exec(exec_cmd: str) -> str:
    lower = exec_cmd.lower()
    if "msedge" in lower or "microsoft-edge" in lower:
        return "msedge"
    if "chromium" in lower and "google-chrome" not in lower:
        return "chromium"
    return "chrome"


def normalize_chrome_pwa_wmclass(
    startup_wmclass: str = "",
    desktop_id: str = "",
    exec_cmd: str = "",
) -> str:
    """Map Chromium X11-era crx_* StartupWMClass to the Wayland app_id Hyprland reports."""
    startup = startup_wmclass.strip()
    desktop_id = desktop_id.strip()

    if CHROME_WAYLAND_DESKTOP_RE.match(desktop_id):
        return desktop_id
    if startup and CHROME_WAYLAND_WMCLASS_RE.match(startup):
        return startup

    crx = CRX_WMCLASS_RE.match(startup)
    if crx:
        app_id = crx.group("appid")
        prefix = browser_prefix_from_exec(exec_cmd)
        profile = profile_suffix_from_exec(exec_cmd)
        return f"{prefix}-{app_id}-{profile}"

    return startup


def profile_dir_from_exec(exec_cmd: str) -> str:
    match = PROFILE_DIR_RE.search(exec_cmd)
    if not match:
        return "Default"
    profile = match.group(1) or match.group(2) or match.group(3)
    return profile.strip()


def chrome_pwa_launch_argv(exec_cmd: str) -> list[str]:
    exec_cmd = re.sub(r" %[a-zA-Z]", "", exec_cmd or "").strip()
    app_id_match = re.search(r"--app-id=([a-z0-9]+)", exec_cmd, re.I)
    if not app_id_match:
        return []
    app_id = app_id_match.group(1)
    profile = profile_dir_from_exec(exec_cmd)

    if re.search(r"flatpak|com\.google\.Chrome", exec_cmd, re.I):
        return [
            "flatpak",
            "run",
            "com.google.Chrome",
            f"--profile-directory={profile}",
            f"--app-id={app_id}",
        ]

    if re.search(r"msedge|microsoft-edge|com\.microsoft\.Edge", exec_cmd, re.I):
        if re.search(r"flatpak|com\.microsoft\.Edge", exec_cmd, re.I):
            return [
                "flatpak",
                "run",
                "com.microsoft.Edge",
                f"--profile-directory={profile}",
                f"--app-id={app_id}",
            ]
        edge_match = re.search(r"(/\S*(?:microsoft-edge|msedge)\S*)", exec_cmd, re.I)
        edge_bin = edge_match.group(1) if edge_match else "microsoft-edge-stable"
        return [edge_bin, f"--profile-directory={profile}", f"--app-id={app_id}"]

    chrome_match = re.search(r"(/\S*google-chrome(?:-stable)?)", exec_cmd, re.I)
    if chrome_match:
        chrome_bin = chrome_match.group(1)
    elif re.search(r"/opt/google/chrome/google-chrome", exec_cmd, re.I):
        chrome_bin = "/opt/google/chrome/google-chrome"
    elif re.search(r"chromium", exec_cmd, re.I) and not re.search(r"google-chrome", exec_cmd, re.I):
        chromium_match = re.search(r"(/\S*chromium\S*)", exec_cmd, re.I)
        chrome_bin = chromium_match.group(1) if chromium_match else "chromium"
    elif re.search(r"brave", exec_cmd, re.I):
        brave_match = re.search(r"(/\S*brave\S*)", exec_cmd, re.I)
        chrome_bin = brave_match.group(1) if brave_match else "brave"
    else:
        chrome_bin = "google-chrome-stable"

    if chrome_bin == "/opt/google/chrome/google-chrome":
        chrome_bin = "google-chrome-stable"

    return [chrome_bin, f"--profile-directory={profile}", f"--app-id={app_id}"]


def parse_desktop_exec(exec_cmd: str) -> list[str]:
    exec_cmd = re.sub(r" %[a-zA-Z]", "", exec_cmd or "").strip()
    if not exec_cmd:
        return []

    pwa_argv = chrome_pwa_launch_argv(exec_cmd)
    if pwa_argv:
        return pwa_argv

    parts: list[str] = []
    for match in re.finditer(r"'([^']*)'|\"([^\"]*)\"|(\S+)", exec_cmd):
        parts.append(match.group(1) or match.group(2) or match.group(3))
    return parts


def launch_argv(desktop_id: str = "", startup_wmclass: str = "", exec_cmd: str = "") -> list[str]:
    exec_cmd = re.sub(r" %[a-zA-Z]", "", exec_cmd or "").strip()
    if exec_cmd:
        return parse_desktop_exec(exec_cmd)
    return []


def resolve_wmclass(
    desktop_id: str = "",
    startup_wmclass: str = "",
    exec_cmd: str = "",
) -> str:
    exec_cmd = re.sub(r" %[a-zA-Z]", "", exec_cmd or "")
    startup_wmclass = (startup_wmclass or "").strip()
    desktop_id = (desktop_id or "").strip()

    if startup_wmclass:
        normalized = normalize_chrome_pwa_wmclass(startup_wmclass, desktop_id, exec_cmd)
        if normalized:
            return normalized

    if CHROME_WAYLAND_DESKTOP_RE.match(desktop_id):
        return desktop_id

    steam_match = re.search(r"steam://rungameid/(\d+)", exec_cmd)
    if steam_match:
        return f"steam_app_{steam_match.group(1)}"

    if exec_cmd:
        return Path(exec_cmd.split()[0]).name.lower()
    return ""


def wmclass_from_fields(
    fields: dict[str, str],
    exec_cmd: str,
    desktop_id: str = "",
) -> str:
    exec_cmd = re.sub(r" %[a-zA-Z]", "", exec_cmd or "")
    startup_wmclass = fields.get("StartupWMClass", "")
    if startup_wmclass:
        normalized = normalize_chrome_pwa_wmclass(startup_wmclass, desktop_id, exec_cmd)
        if normalized:
            return normalized
    steam_match = re.search(r"steam://rungameid/(\d+)", exec_cmd)
    if steam_match:
        return f"steam_app_{steam_match.group(1)}"
    if exec_cmd:
        return Path(exec_cmd.split()[0]).name.lower()
    return ""


def build_index(size: int = 48) -> dict[str, str]:
    index: dict[str, str] = {}
    for path, fields in iter_desktop_entries():
        exec_cmd = re.sub(r" %[a-zA-Z]", "", fields.get("Exec", ""))
        wmclass = wmclass_from_fields(fields, exec_cmd, path.stem)
        names = [
            fields.get("Icon", ""),
            path.stem,
            wmclass,
            fields.get("StartupWMClass", ""),
        ]
        steam_match = re.search(r"steam://rungameid/(\d+)", exec_cmd)
        if steam_match:
            names.append(f"steam_app_{steam_match.group(1)}")
            names.append(f"steam_icon_{steam_match.group(1)}")
        for name in names:
            key = normalize_icon_name(name)
            if not key or key in index:
                continue
            hit = lookup_icon(key, size)
            if hit:
                index[key] = hit
                lower = key.lower()
                if lower not in index:
                    index[lower] = hit
    return index


def index_stamp() -> str:
    count = 0
    newest = 0
    for folder in DESKTOP_DIRS:
        if not folder.is_dir():
            continue
        for path in folder.glob("*.desktop"):
            count += 1
            try:
                newest = max(newest, int(path.stat().st_mtime))
            except OSError:
                pass
    return f"{INDEX_VERSION}:{count}:{newest}:{get_icon_theme()}"


def write_index(path: Path, index: dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    stamp_path = path.with_suffix(".stamp")
    stamp_path.write_text(index_stamp(), encoding="utf-8")


def load_or_build_index(path: Path, force: bool = False) -> dict[str, str]:
    stamp_path = path.with_suffix(".stamp")
    stamp = index_stamp()
    if (
        not force
        and path.is_file()
        and stamp_path.is_file()
        and stamp_path.read_text(encoding="utf-8") == stamp
    ):
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    index = build_index()
    write_index(path, index)
    return index


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("usage: icon_resolve.py {lookup|resolve|wmclass|launch-argv|build-index} ...", file=sys.stderr)
        return 1

    cmd = args[0]
    force = "--force" in args

    if cmd == "lookup":
        name = args[1] if len(args) > 1 else ""
        path = lookup_icon(name)
        if path:
            print(path)
        return 0 if path else 1

    if cmd == "resolve":
        icon = args[1] if len(args) > 1 else ""
        desktop_id = args[2] if len(args) > 2 else ""
        wmclass = args[3] if len(args) > 3 else ""
        exec_cmd = args[4] if len(args) > 4 else ""
        path = resolve_app_icon(icon, desktop_id, wmclass, exec_cmd)
        if path:
            print(path)
        return 0 if path else 1

    if cmd == "wmclass":
        desktop_id = args[1] if len(args) > 1 else ""
        startup_wmclass = args[2] if len(args) > 2 else ""
        exec_cmd = args[3] if len(args) > 3 else ""
        print(resolve_wmclass(desktop_id, startup_wmclass, exec_cmd))
        return 0

    if cmd == "launch-argv":
        exec_cmd = args[1] if len(args) > 1 else ""
        print(json.dumps(launch_argv(exec_cmd=exec_cmd)))
        return 0

    if cmd == "build-index":
        out = Path(args[1]) if len(args) > 1 and not args[1].startswith("-") else HOME / ".config/cloud-center/settings/quickshell/icon_index.json"
        index = load_or_build_index(out, force=force)
        json.dump(index, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    print("usage: icon_resolve.py {lookup|resolve|wmclass|build-index} ...", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
