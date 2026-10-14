"""Cloud Center — static native-page metadata shared by the UI and search catalog."""
from __future__ import annotations

NATIVE_PAGES: list[dict] = [
    {"id": "__cursor__", "title": "Cursor", "icon": "󰍽", "flag": "--page=cursor",
     "keywords": ["mouse pointer", "cursor size", "cursor theme", "hide cursor"]},
    {"id": "__mon__", "title": "Monitors", "icon": "󰍹", "flag": "--monitors",
     "keywords": ["display", "resolution", "refresh rate", "scale", "rotation", "HDR", "VRR"]},
    {"id": "__bt__", "title": "Bluetooth", "icon": "󰂯", "flag": "--bluetooth"},
    {"id": "__wifi__", "title": "Wi-Fi", "icon": "󰤨", "flag": "--wifi",
     "keywords": ["wifi", "wireless", "network", "internet"]},
    {"id": "__audio__", "title": "Audio", "icon": "󰓃", "flag": "--audio",
     "keywords": ["sound", "volume", "speaker", "microphone", "input device", "output device"]},
    {"id": "__recording__", "title": "Recording", "icon": "󰀀", "flag": "--page=recording"},
    {"id": "__region__", "title": "Region & Time", "icon": "󰍎", "flag": "--region",
     "keywords": ["timezone", "date", "clock", "location"]},
    {"id": "__hkbm__", "title": "Keybind Manager", "icon": "󰌌", "flag": "--keybinds"},
    {"id": "__rules__", "title": "Rules & Startup", "icon": "󰒓", "flag": "--page=__rules__",
     "keywords": ["window rules", "autostart", "workspace rules"]},
    {"id": "__battery__", "title": "Battery", "icon": "󰁹", "flag": "--page=battery"},
]
