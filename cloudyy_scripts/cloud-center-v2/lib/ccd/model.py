"""
Cloud Center — lib/ccd/model.py
Builds the page model the QML frontend renders: config.yaml pages plus the
native (not-yet-ported) pages, with GTK symbolic icon names translated to
Nerd Font glyphs.

Everything the frontend needs for first paint is in the model — including
initial toggle/slider/selection values — so no follow-up round-trips are
needed before the window can draw.
"""
from __future__ import annotations

import logging
from pathlib import Path

import yaml

import lib.utility as utility
from lib.ccd import protocol

log = logging.getLogger(__name__)

SCRIPT_DIR = Path(__file__).resolve().parents[2]
CONFIG_PATH = SCRIPT_DIR / "config.yaml"
GTK_APP = SCRIPT_DIR / "cloud-center.py"

# Keep in sync with ACTIVE_SHELL_TAB in cloud-center.py (updated by installer).
ACTIVE_SHELL_TAB = "quickshell"

# ── Icons ─────────────────────────────────────────────────────────────────────
# GTK symbolic icon names → Nerd Font glyphs. THE one place icons are defined;
# edit here to change any icon. Names not listed fall back to DEFAULT_ICON.

DEFAULT_ICON = "\U000f0493"  # 󰒓 cog

ICON_MAP: dict[str, str] = {
    "application-x-executable-symbolic":      "\U000f0614",  # 󰘔 application
    "applications-graphics-symbolic":         "\U000f00e3",  # 󰃣 brush
    "applications-science-symbolic":          "\U000f0668",  # 󰙨 test tube
    "audio-speakers-symbolic":                "\U000f04c3",  # 󰓃 speaker
    "battery-good-symbolic":                  "\U000f0079",  # 󰁹 battery
    "bluetooth-active-symbolic":              "\U000f00af",  # 󰂯 bluetooth
    "clock-symbolic":                         "\U000f0954",  # 󰥔 clock
    "computer-symbolic":                      "\U000f01c4",  # 󰇄 desktop
    "display-brightness-symbolic":            "\U000f00df",  # 󰃟 brightness
    "drive-harddisk-symbolic":                "\U000f02ca",  # 󰋊 harddisk
    "edit-clear-symbolic":                    "\U000f00e2",  # 󰃢 broom
    "face-smile-symbolic":                    "\U000f0c6b",  # 󰱫 smile
    "focus-windows-symbolic":                 "\U000f05af",  # 󰖯 window
    "folder-symbolic":                        "\U000f024b",  # 󰉋 folder
    "go-home-symbolic":                       "\U000f02dc",  # 󰋜 home
    "go-next-symbolic":                       "\U000f0142",  # 󰅂 chevron right
    "input-keyboard-symbolic":                "\U000f030c",  # 󰌌 keyboard
    "input-mouse-symbolic":                   "\U000f037d",  # 󰍽 mouse
    "input-touchpad-symbolic":                "\U000f07f8",  # 󰟸 touchpad
    "mark-location-symbolic":                 "\U000f034e",  # 󰍎 map marker
    "media-playback-pause-symbolic":          "\U000f03e4",  # 󰏤 pause
    "media-playback-start-symbolic":          "\U000f040a",  # 󰐊 play
    "media-playlist-repeat-symbolic":         "\U000f0456",  # 󰑖 repeat
    "network-wireless-signal-good-symbolic":  "\U000f0928",  # 󰤨 wifi
    "preferences-color-symbolic":             "\U000f03d8",  # 󰏘 palette
    "preferences-desktop-appearance-symbolic": "\U000f0e0c", # 󰸌 palette swatch
    "preferences-desktop-keyboard-symbolic":  "\U000f030c",  # 󰌌 keyboard
    "preferences-desktop-wallpaper-symbolic": "\U000f0e09",  # 󰸉 wallpaper
    "preferences-system-symbolic":            "\U000f0493",  # 󰒓 cog
    "preferences-system-time-symbolic":       "\U000f0954",  # 󰥔 clock
    "software-update-available-symbolic":     "\U000f06b0",  # 󰚰 update
    "utilities-terminal-symbolic":            "\U000f018d",  # 󰆍 console
    "video-display-symbolic":                 "\U000f0379",  # 󰍹 monitor
    "view-grid-symbolic":                     "\U000f0570",  # 󰕰 grid
    "view-refresh-symbolic":                  "\U000f0450",  # 󰑐 refresh
    "view-reveal-symbolic":                   "\U000f0208",  # 󰈈 eye
    "weather-clear-night-symbolic":           "\U000f0594",  # 󰖔 night
    "weather-fog-symbolic":                   "\U000f0591",  # 󰖑 fog
    "weather-overcast-symbolic":              "\U000f0590",  # 󰖐 cloudy
    "window-minimize-symbolic":               "\U000f05b0",  # 󰖰 minimize
    "zoom-fit-best-symbolic":                 "\U000f0a6d",  # 󰩭 fit
    "zoom-in-symbolic":                       "\U000f06ed",  # 󰛭 zoom in
}

WALLPAPER_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}

# ── Native pages ──────────────────────────────────────────────────────────────
# Pages still implemented by the GTK app. Shown in the sidebar; opening one
# deep-links into the legacy app until its port lands (spec Phases 2-5).

NATIVE_PAGES: list[dict] = [
    {"id": "__cursor__",  "title": "Cursor",          "icon": "input-mouse-symbolic",                  "flag": "--page=cursor"},
    {"id": "__mon__",     "title": "Monitors",        "icon": "video-display-symbolic",                "flag": "--monitors"},
    {"id": "__bt__",      "title": "Bluetooth",       "icon": "bluetooth-active-symbolic",             "flag": "--bluetooth"},
    {"id": "__wifi__",    "title": "Wi-Fi",           "icon": "network-wireless-signal-good-symbolic", "flag": "--wifi"},
    {"id": "__audio__",   "title": "Audio",           "icon": "audio-speakers-symbolic",               "flag": "--audio"},
    {"id": "__region__",  "title": "Region & Time",   "icon": "mark-location-symbolic",                "flag": "--region"},
    {"id": "__hkbm__",    "title": "Keybind Manager", "icon": "input-keyboard-symbolic",               "flag": "--keybinds"},
    {"id": "__rules__",   "title": "Rules & Startup", "icon": "preferences-system-symbolic",           "flag": "--page=__rules__"},
    {"id": "__battery__", "title": "Battery",         "icon": "battery-good-symbolic",                 "flag": "--page=battery"},
]

# Sidebar structure (mirrors the GTK sidebar). Home is pinned separately.
CATEGORIES: list[tuple[str, list[str]]] = [
    ("Visuals",         ["appearance", "wallpapers", ACTIVE_SHELL_TAB, "hyprland", "terminal", "__rules__"]),
    ("Input & Display", ["input", "__cursor__", "__mon__", "__hkbm__"]),
    ("System",          ["__bt__", "__wifi__", "__audio__", "__region__", "__battery__"]),
]

# Raw item configs by item id, for actions.py / state.py. Rebuilt on load_model.
ITEMS: dict[str, dict] = {}

# Symbolic names seen without an ICON_MAP entry during the last load.
UNMAPPED_ICONS: set[str] = set()


def icon_glyph(icon_name: str) -> str:
    """Translate a GTK symbolic name to a Nerd Font glyph; pass glyphs through."""
    if not icon_name:
        return ""
    if any(ord(ch) > 127 for ch in icon_name):
        return icon_name
    glyph = ICON_MAP.get(icon_name)
    if glyph is None:
        UNMAPPED_ICONS.add(icon_name)
        log.warning("No glyph mapped for icon %r, using default", icon_name)
        return DEFAULT_ICON
    return glyph


def unmapped_icons() -> set[str]:
    return set(UNMAPPED_ICONS)


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


def wallpaper_list(directory: str) -> list[str]:
    path = Path(directory).expanduser()
    if not path.is_dir():
        return []
    files = [p for p in path.iterdir() if p.suffix.lower() in WALLPAPER_EXTS]
    return sorted(str(p) for p in files)


def build_item(raw: dict, item_id: str) -> dict:
    """Flatten one YAML item into the shape the frontend renders."""
    item_type = raw.get("type", "")
    props = raw.get("properties", {}) or {}

    item = {**props, "id": item_id, "type": item_type}
    item["icon"] = icon_glyph(props.get("icon", ""))

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
            item["wallpapers"] = wallpaper_list(props.get("directory", ""))
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
        "icon": icon_glyph(page_cfg.get("icon", "")),
        "sections": sections,
    }


def build_native_page(entry: dict) -> dict:
    return {
        "id": entry["id"],
        "kind": "native",
        "title": entry["title"],
        "icon": icon_glyph(entry["icon"]),
        "deep_link": ["python3", str(GTK_APP), entry["flag"]],
    }


def load_model(config_path: Path = CONFIG_PATH) -> dict:
    """Read config.yaml and return the full frontend model."""
    ITEMS.clear()
    UNMAPPED_ICONS.clear()

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
