"""Pure normalization and persistence policy for Island integrations."""
from __future__ import annotations

import json
import os
from pathlib import Path
import tempfile
from typing import Any


KNOWN_IDS = ("notifications", "timer", "media", "agents")


def default_settings() -> dict[str, Any]:
    return {
        "version": 1,
        "order": list(KNOWN_IDS),
        "enabled": {integration_id: True for integration_id in KNOWN_IDS},
    }


def _is_valid(value: Any) -> bool:
    if not isinstance(value, dict) or isinstance(value.get("version"), bool):
        return False
    if value.get("version") != 1:
        return False
    order = value.get("order")
    enabled = value.get("enabled")
    return (
        isinstance(order, list)
        and all(isinstance(integration_id, str) for integration_id in order)
        and isinstance(enabled, dict)
        and all(isinstance(state, bool) for state in enabled.values())
    )


def normalize_settings(
    value: Any, last_valid: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if not _is_valid(value):
        value = last_valid if _is_valid(last_valid) else default_settings()

    order: list[str] = []
    for integration_id in value["order"]:
        if integration_id in KNOWN_IDS and integration_id not in order:
            order.append(integration_id)
    order.extend(integration_id for integration_id in KNOWN_IDS if integration_id not in order)
    return {
        "version": 1,
        "order": order,
        "enabled": {
            integration_id: value["enabled"].get(integration_id, True)
            for integration_id in KNOWN_IDS
        },
    }


def load_settings(path: str | Path) -> dict[str, Any]:
    path = Path(path)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return default_settings()
    return normalize_settings(value)


def save_settings(path: str | Path, value: Any) -> dict[str, Any]:
    if not _is_valid(value):
        raise ValueError("invalid Island integration settings")
    normalized = normalize_settings(value)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix=".island-integrations.", dir=path.parent,
    )
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(normalized, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary_path.replace(path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise
    return normalized
