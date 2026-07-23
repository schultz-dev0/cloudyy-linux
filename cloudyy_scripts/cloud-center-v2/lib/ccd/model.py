"""
Cloud Center — lib/ccd/model.py
Builds the page model the QML frontend renders: config.yaml pages plus the
dedicated native QML editors (Wi-Fi, Audio, …). Icons are literal Nerd Font
glyphs already — config.yaml's `icon:` fields and NATIVE_PAGES entries hold
the actual character, no name-to-glyph translation layer.

Everything the frontend needs for first paint is in the model — including
initial toggle/slider/selection values — so no follow-up round-trips are
needed before the window can draw.
"""
from __future__ import annotations

import hashlib
import logging
from pathlib import Path

import yaml

import lib.utility as utility
from lib.ccd import protocol

try:
    from PIL import Image as _PILImage
except ImportError:
    _PILImage = None

log = logging.getLogger(__name__)

SCRIPT_DIR = Path(__file__).resolve().parents[2]
CONFIG_PATH = SCRIPT_DIR / "config.yaml"

THUMB_DIR = utility.CACHE_DIR / "thumbs"
THUMB_SIZE = 256  # long edge; the grid only ever displays these at ~264px

# Keep in sync with installer ACTIVE_SHELL_TAB when that still exists.
ACTIVE_SHELL_TAB = "quickshell"

WALLPAPER_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
THEME_STATE = Path.home() / ".config" / "hypr" / "theme_state" / "state.conf"

# ── Native pages ──────────────────────────────────────────────────────────────
# Pages still implemented by the GTK app. Shown in the sidebar; opening one
# deep-links into the legacy app until its port lands (spec Phases 2-5).

NATIVE_PAGES: list[dict] = [
    {"id": "__cursor__",  "title": "Cursor",          "icon": "\U000f037d", "flag": "--page=cursor"},     # 󰍽 mouse
    {"id": "__mon__",     "title": "Monitors",        "icon": "\U000f0379", "flag": "--monitors"},        # 󰍹 monitor
    {"id": "__bt__",      "title": "Bluetooth",       "icon": "\U000f00af", "flag": "--bluetooth"},       # 󰂯 bluetooth
    {"id": "__wifi__",    "title": "Wi-Fi",           "icon": "\U000f0928", "flag": "--wifi"},            # 󰤨 wifi
    {"id": "__audio__",   "title": "Audio",           "icon": "\U000f04c3", "flag": "--audio"},           # 󰓃 speaker
    {"id": "__region__",  "title": "Region & Time",   "icon": "\U000f034e", "flag": "--region"},          # 󰍎 map marker
    {"id": "__hkbm__",    "title": "Keybind Manager", "icon": "\U000f030c", "flag": "--keybinds"},        # 󰌌 keyboard
    {"id": "__rules__",   "title": "Rules & Startup", "icon": "\U000f0493", "flag": "--page=__rules__"},  # 󰒓 cog
    {"id": "__battery__", "title": "Battery",         "icon": "\U000f0079", "flag": "--page=battery"},    # 󰁹 battery
]

# Sidebar structure (mirrors the GTK sidebar). Home is pinned separately.
CATEGORIES: list[tuple[str, list[str]]] = [
    ("Visuals",         ["appearance", "wallpapers", ACTIVE_SHELL_TAB, "hyprland", "terminal", "__rules__"]),
    ("Input & Display", ["input", "__cursor__", "__mon__", "__hkbm__"]),
    ("System",          ["__bt__", "__wifi__", "__audio__", "__region__", "__battery__"]),
]

# Raw item configs by item id, for actions.py / state.py. Rebuilt on load_model.
ITEMS: dict[str, dict] = {}

# ── Initial values (correct first paint, no round-trips) ────────────────────


def toggle_value(props: dict) -> bool:
    default = props.get("default", False)
    if not isinstance(default, bool):
        default = str(default).lower() in {"true", "yes", "1", "on"}
    key = props.get("key", "")
    return utility.load_setting(key, default) if key else default


def slider_value(props: dict) -> float:
    default = float(props.get("default", props.get("min", 0)))
    key = props.get("key", "")
    return utility.load_setting(key, default) if key else default


def selection_value(props: dict) -> str:
    options = [str(o) for o in props.get("options", [])]
    key = props.get("key", "")
    saved = utility.load_setting(key, "") if key else ""
    if saved in options:
        return saved
    return options[0] if options else ""


def multi_selection_values(props: dict) -> list[str]:
    options = [str(o) for o in props.get("options", [])]
    key = props.get("key", "")
    saved = utility.load_setting(key, "") if key else ""
    values = [part.strip() for part in saved.split(",") if part.strip() in options]
    if not values and options:
        values = [options[0]]
    return values


def theme_mode() -> str:
    """THEME_MODE from theme state; falls back to the dark_mode setting."""
    try:
        for line in THEME_STATE.read_text(encoding="utf-8").splitlines():
            if line.startswith("THEME_MODE="):
                val = line[len("THEME_MODE="):].strip().strip("\"'").lower()
                if val in {"light", "dark"}:
                    return val
    except OSError:
        pass
    return "dark" if utility.load_setting("theme/dark_mode", False) else "light"


def wallpaper_thumb(path: Path) -> str:
    """Disk-cached, downscaled copy of a wallpaper for the picker grid.

    Some wallpapers are 15+ MB / 6000px+ PNGs; Qt has no scaled PNG decode
    path (unlike JPEG), so handing those straight to the QML Image element
    means a full-resolution decode on every single page visit. Falls back to
    the original path if Pillow is missing or decoding fails — the tile just
    loads at full cost like before, nothing breaks.
    """
    if _PILImage is None:
        return str(path)
    try:
        mtime_ns = path.stat().st_mtime_ns
    except OSError:
        return str(path)
    key = hashlib.sha1(f"{path}:{mtime_ns}".encode()).hexdigest()
    cached = THUMB_DIR / f"{key}.jpg"
    if cached.exists():
        return str(cached)
    try:
        THUMB_DIR.mkdir(parents=True, exist_ok=True)
        with _PILImage.open(path) as img:
            img.thumbnail((THUMB_SIZE, THUMB_SIZE))
            img.convert("RGB").save(cached, "JPEG", quality=85)
        return str(cached)
    except Exception as e:
        log.warning("wallpaper_thumb failed for %s: %s", path, e)
        return str(path)


def wallpaper_list(directory: str, max_items: int = 100) -> list[dict]:
    if not directory:
        return []
    base = Path(directory).expanduser().resolve()
    if not base.is_dir():
        return []
    # Mirror the GTK picker: prefer <dir>/<Mode> plus user_wallpapers/<Mode>,
    # scanned recursively; flat scan of the directory itself otherwise.
    mode = theme_mode().capitalize()
    roots = [r for r in (base / mode, base / "user_wallpapers" / mode) if r.is_dir()]
    if roots:
        files = [
            p for root in roots for p in root.rglob("*")
            if p.is_file() and p.suffix.lower() in WALLPAPER_EXTS
        ]
    else:
        files = [
            p for p in base.iterdir()
            if p.is_file() and p.suffix.lower() in WALLPAPER_EXTS
        ]
    # GTK picker parity: cap the grid (rows.py max_items default 100).
    paths = sorted({str(p) for p in files})[:max_items]
    return [{"path": p, "thumb": wallpaper_thumb(Path(p))} for p in paths]


def build_item(raw: dict, item_id: str) -> dict:
    """Flatten one YAML item into the shape the frontend renders."""
    item_type = raw.get("type", "")
    props = raw.get("properties", {}) or {}

    item = {**props, "id": item_id, "type": item_type}
    item["icon"] = props.get("icon", "") or ""

    match item_type:
        case "toggle":
            item["value"] = toggle_value(props)
        case "slider":
            item["value"] = slider_value(props)
        case "selection":
            item["value"] = selection_value(props)
        case "multi_selection":
            item["values"] = multi_selection_values(props)
        case "label":
            value_cfg = raw.get("value", {}) or {}
            static = value_cfg.get("type") == "static"
            item["text"] = str(value_cfg.get("text", "")) if static else "…"
        case "wallpaper_picker":
            item["wallpapers"] = wallpaper_list(
                props.get("directory", ""), int(props.get("max_items", 100))
            )
            item["current"] = utility.load_setting(props.get("key", ""), "")

    return item


def build_yaml_page(page_cfg: dict) -> dict:
    page_id = page_cfg.get("id", "")
    sections = []
    for section_index, section_cfg in enumerate(page_cfg.get("layout", []) or []):
        section_props = section_cfg.get("properties", {}) or {}
        items = []
        for item_index, raw in enumerate(section_cfg.get("items", []) or []):
            item_id = f"{page_id}/{section_index}/{item_index}"
            ITEMS[item_id] = raw
            items.append(build_item(raw, item_id))
        sections.append({"title": section_props.get("title", ""), "items": items})

    return {
        "id": page_id,
        "kind": "yaml",
        "title": page_cfg.get("title", ""),
        "icon": page_cfg.get("icon", "") or "",
        "sections": sections,
    }


# Pages with dedicated QML editors get their own `kind` so the frontend
# Loader can pick a native component instead of YamlPage.
NATIVE_KIND_OVERRIDES: dict[str, str] = {
    "__audio__": "audio",
    "__battery__": "battery",
    "__bt__": "bluetooth",
    "__cursor__": "cursor",
    "__mon__": "monitors",
    "__hkbm__": "keybinds",
    "__region__": "region",
    "__rules__": "rules_startup",
    "__wifi__": "wifi",
}


def build_native_page(entry: dict) -> dict:
    kind = NATIVE_KIND_OVERRIDES.get(entry["id"])
    if kind is None:
        raise ValueError(f"native page {entry['id']} has no QML kind override")
    return {
        "id": entry["id"],
        "kind": kind,
        "title": entry["title"],
        "icon": entry["icon"],
    }


def load_model(config_path: Path = CONFIG_PATH) -> dict:
    """Read config.yaml and return the full frontend model."""
    ITEMS.clear()

    config = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    pages = [
        build_yaml_page(page_cfg)
        for page_cfg in config.get("pages", [])
        if page_cfg.get("id")
    ]
    pages += [build_native_page(entry) for entry in NATIVE_PAGES]

    return {
        "pages": pages,
        "categories": [
            {"title": title, "pages": page_ids} for title, page_ids in CATEGORIES
        ],
        "pinned": [{"id": "home", "title": "System Overview"}],
    }


def get_model(params: dict) -> dict:
    return load_model()


protocol.register("get_model", get_model)
