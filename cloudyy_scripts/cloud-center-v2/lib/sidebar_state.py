"""Sidebar state management — categories, favorites, collapsible state persistence."""
from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

STATE_DIR = Path.home() / ".config" / "cloud-center"
STATE_FILE = STATE_DIR / "sidebar_state.json"


class SidebarState:
    """Manages sidebar expand/collapse state and favorites persistence."""

    def __init__(self) -> None:
        self.favorites: set[str] = set()
        self.expanded_categories: set[str] = set()
        self._load()

    def _load(self) -> None:
        """Load state from disk, or initialize defaults."""
        if not STATE_FILE.exists():
            self._init_defaults()
            return

        try:
            data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
            self.favorites = set(data.get("favorites", []))
            self.expanded_categories = set(data.get("expanded_categories", []))
        except Exception as e:
            log.warning("Failed to load sidebar state: %s, using defaults", e)
            self._init_defaults()

    def _init_defaults(self) -> None:
        """Initialize default state: all categories expanded, no favorites."""
        self.favorites = set()
        self.expanded_categories = {
            "quick_settings",
            "appearance",
            "workspace",
            "windows",
            "system",
            "advanced",
        }
        self.save()

    def save(self) -> None:
        """Persist state to disk (atomic)."""
        STATE_DIR.mkdir(mode=0o755, parents=True, exist_ok=True)
        data = {
            "favorites": sorted(self.favorites),
            "expanded_categories": sorted(self.expanded_categories),
        }
        tmp_path = STATE_FILE.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        tmp_path.replace(STATE_FILE)

    def toggle_favorite(self, page_id: str) -> bool:
        """Toggle favorite status. Returns True if now favorited."""
        if page_id in self.favorites:
            self.favorites.discard(page_id)
            self.save()
            return False
        else:
            self.favorites.add(page_id)
            self.save()
            return True

    def is_favorite(self, page_id: str) -> bool:
        """Check if page is favorited."""
        return page_id in self.favorites

    def toggle_category(self, category_id: str) -> bool:
        """Toggle category expanded state. Returns True if now expanded."""
        if category_id in self.expanded_categories:
            self.expanded_categories.discard(category_id)
            self.save()
            return False
        else:
            self.expanded_categories.add(category_id)
            self.save()
            return True

    def is_expanded(self, category_id: str) -> bool:
        """Check if category is expanded."""
        return category_id in self.expanded_categories


# ── Sidebar category definitions ────────────────────────────────────────────


CATEGORIES = {
    "quick_settings": {
        "label": "Quick Settings",
        "icon": "⚡",
        "description": "Frequently-changed toggles",
    },
    "appearance": {
        "label": "Appearance",
        "icon": "󰨨",
        "description": "Theme, wallpapers, colors",
    },
    "workspace": {
        "label": "Workspace",
        "icon": "󰪴",
        "description": "Layout, animations, gaps",
    },
    "windows": {
        "label": "Windows",
        "icon": "󰒙",
        "description": "Window behavior, keybinds",
    },
    "system": {
        "label": "System",
        "icon": "⚙️",
        "description": "Updates, reloads, tools",
    },
    "advanced": {
        "label": "Advanced",
        "icon": "󰒓",
        "description": "Config manager, advanced settings",
    },
}


def get_category_for_page(page_id: str) -> str:
    """Map page IDs to categories. Used for organizing YAML pages."""
    # Defaults based on page_id patterns
    if page_id == "__hcm__":
        return "advanced"
    if page_id == "__hkbm__":
        return "windows"
    if page_id in ("appearance", "online_wallpapers"):
        return "appearance"
    if page_id in ("hyprland",):
        return "workspace"
    if page_id in ("waybar",):
        return "system"
    if page_id in ("tools",):
        return "system"
    if page_id == "home":
        return "quick_settings"
    return "system"  # fallback
