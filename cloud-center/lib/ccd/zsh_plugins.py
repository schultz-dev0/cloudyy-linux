"""GTK-free ccd protocol adapter for the Zsh Extension Browser row."""
from __future__ import annotations

from typing import Any

from lib import zsh_plugins_core
from lib.ccd import protocol


def list_zsh_plugins(params: dict[str, Any]) -> dict[str, Any]:
    query = str(params.get("query", "") or "")
    enabled_only = bool(params.get("enabled_only", False))
    raw_limit = params.get("limit", zsh_plugins_core.VISIBLE_LIMIT)
    try:
        limit = int(raw_limit)
    except (TypeError, ValueError) as exc:
        raise ValueError("limit must be an integer") from exc
    return zsh_plugins_core.list_plugins(
        query=query,
        enabled_only=enabled_only,
        limit=limit,
    )


def set_zsh_plugin(params: dict[str, Any]) -> dict[str, Any]:
    name = params.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("name must be a non-empty string")
    enabled = params.get("enabled")
    if not isinstance(enabled, bool):
        raise ValueError("enabled must be a boolean")
    return zsh_plugins_core.set_plugin_enabled(name.strip(), enabled)


protocol.register("list_zsh_plugins", list_zsh_plugins)
protocol.register("set_zsh_plugin", set_zsh_plugin)
