#!/usr/bin/env python3
"""Build App Library catalog from .desktop entries."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SERVICES_DIR = SCRIPT_DIR.parent.parent.parent / "overview" / "services"
sys.path.insert(0, str(SERVICES_DIR))
from icon_resolve import INDEX_VERSION, get_icon_theme, read_desktop, resolve_app_icon, wmclass_from_fields  # noqa: E402

MAP_FILE = SCRIPT_DIR / "category-map.json"
CATALOG_VERSION = "desktop-entry-v3"
HOME = Path.home()
CACHE_DIR = HOME / ".config/cloud-center/settings/quickshell"
CACHE_FILE = CACHE_DIR / "app_catalog.json"
STAMP_FILE = CACHE_DIR / "app_catalog.stamp"
DESKTOP_DIRS = tuple(dict.fromkeys(
    Path(folder) / "applications" for folder in
    [os.environ.get("XDG_DATA_HOME", str(HOME / ".local/share")),
     *os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")]
    if folder
))
EXEC_FIELD_RE = re.compile(r" %[a-zA-Z]")


def map_categories(raw: str, cat_map: dict[str, str]) -> list[str]:
    if not raw:
        return []
    out: list[str] = []
    seen: set[str] = set()
    for part in raw.split(";"):
        key = part.replace(" ", "")
        if not key:
            continue
        label = cat_map.get(key) or "Other"
        if label not in seen:
            seen.add(label)
            out.append(label)
    return out


def desktop_stamp() -> str:
    digest = hashlib.sha256()
    for folder in DESKTOP_DIRS:
        if not folder.is_dir():
            continue
        try:
            entries = sorted(folder.rglob("*.desktop"))
        except OSError:
            continue
        for path in entries:
            try:
                stat = path.stat()
                digest.update(f"{path}:{stat.st_mtime_ns}:{stat.st_size}".encode())
            except OSError:
                pass
    map_mtime = int(MAP_FILE.stat().st_mtime) if MAP_FILE.is_file() else 0
    theme = get_icon_theme()
    return f"{CATALOG_VERSION}:{INDEX_VERSION}:{digest.hexdigest()}:{map_mtime}:{theme}"


def build_catalog() -> list[dict]:
    with MAP_FILE.open(encoding="utf-8") as handle:
        cat_map: dict[str, str] = json.load(handle)

    apps: list[dict] = []
    seen_ids: set[str] = set()

    for folder in DESKTOP_DIRS:
        if not folder.is_dir():
            continue
        try:
            desktops = sorted(folder.rglob("*.desktop"))
        except OSError:
            continue
        for path in desktops:
            app_id = str(path.relative_to(folder).with_suffix("")).replace("/", "-")
            if app_id in seen_ids:
                continue
            seen_ids.add(app_id)

            fields = read_desktop(path)
            if fields.get("NoDisplay") == "true" or fields.get("Hidden") == "true":
                continue

            name = fields.get("Name", "")
            exec_raw = fields.get("Exec", "")
            exec_cmd = EXEC_FIELD_RE.sub("", exec_raw)
            if not name or not exec_cmd:
                continue

            icon = fields.get("Icon", "application-x-executable")
            wmclass = wmclass_from_fields(fields, exec_cmd, app_id)

            exec_base = Path(exec_cmd.split()[0]).name
            icon_path = resolve_app_icon(icon, app_id, wmclass, exec_cmd)

            apps.append(
                {
                    "id": app_id,
                    "name": name,
                    "genericName": fields.get("GenericName", ""),
                    "comment": fields.get("Comment", ""),
                    "icon": icon,
                    "iconPath": icon_path,
                    "desktopPath": str(path),
                    "exec": exec_cmd,
                    "wmclass": wmclass,
                    "categories": map_categories(fields.get("Categories", ""), cat_map),
                }
            )

    apps.sort(key=lambda item: item["name"].casefold())
    return apps


def write_cache(apps: list[dict]) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        CACHE_FILE.write_text(json.dumps(apps, separators=(",", ":")), encoding="utf-8")
        STAMP_FILE.write_text(desktop_stamp(), encoding="utf-8")
    except OSError:
        pass


def load_catalog(force: bool = False) -> list[dict]:
    stamp = desktop_stamp()
    if (
        not force
        and CACHE_FILE.is_file()
        and STAMP_FILE.is_file()
        and STAMP_FILE.read_text(encoding="utf-8") == stamp
    ):
        try:
            return json.loads(CACHE_FILE.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass

    apps = build_catalog()
    write_cache(apps)
    return apps


def category_labels(apps: list[dict]) -> list[str]:
    labels = sorted({cat for app in apps for cat in app.get("categories", [])})
    return ["All", *labels]


def main() -> int:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    force = "--force" in sys.argv

    if cmd == "watch":
        from watch_paths import watch_paths
        watch_paths([*DESKTOP_DIRS, MAP_FILE], recursive=True)
        return 0

    if cmd == "list":
        apps = load_catalog(force=force)
        json.dump(apps, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    if cmd == "categories":
        apps = load_catalog(force=force)
        json.dump(category_labels(apps), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    print("usage: apps-catalog.py {list|categories|watch} [--force]", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
