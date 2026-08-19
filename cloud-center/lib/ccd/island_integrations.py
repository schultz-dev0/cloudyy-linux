"""Cloud Center — lib/ccd/island_integrations.py
Dedicated protocol adapter for Dynamic Island integration settings.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from lib import island_integrations_core
from lib.ccd import protocol


def _settings_path() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME")
    root = Path(config_home) if config_home else Path.home() / ".config"
    return root / "cloud-center/settings/quickshell/island-integrations.json"


def get_island_integrations(_params: dict[str, Any]) -> dict[str, Any]:
    return island_integrations_core.load_settings(_settings_path())


def save_island_integrations(params: Any) -> dict[str, Any]:
    settings = params.get("settings") if isinstance(params, dict) else None
    try:
        return island_integrations_core.save_settings(_settings_path(), settings)
    except OSError as exc:
        raise RuntimeError("Could not save Island integration settings") from exc


protocol.register("get_island_integrations", get_island_integrations)
protocol.register("save_island_integrations", save_island_integrations)
