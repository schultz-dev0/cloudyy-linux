"""Control the persistent Cloud Center audio auto-switch user service."""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from lib import audio_core


SERVICE_NAME = "cloudyy-audio-autoswitch.service"
SERVICE_PROMPT_VERSION = 1
UNIT_PATH = Path.home() / ".config/systemd/user" / SERVICE_NAME


def policy_enabled(config: dict[str, Any]) -> bool:
    """Whether either automatic output-selection policy is active."""
    return bool(config.get("bluetooth_auto_switch", True) or config.get("enabled", False))


def _systemctl(
    args: list[str], run: Any = subprocess.run,
) -> tuple[bool, str]:
    try:
        result = run(
            ["systemctl", "--user", *args], capture_output=True, text=True, timeout=8,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
        return False, str(exc)
    message = (result.stderr or result.stdout or "").strip()
    return result.returncode == 0, message


def service_status(
    run: Any = subprocess.run, unit_path: Path = UNIT_PATH,
) -> dict[str, Any]:
    """Return the installed, enabled, and active state of the user service."""
    if not unit_path.is_file():
        return {
            "present": False,
            "loaded": False,
            "enabled": False,
            "active": False,
            "error": "Service unit is not installed",
        }

    load_ok, load_state = _systemctl(
        ["show", "-p", "LoadState", "--value", SERVICE_NAME], run,
    )
    enabled, enabled_error = _systemctl(["is-enabled", SERVICE_NAME], run)
    active, active_error = _systemctl(["is-active", SERVICE_NAME], run)
    return {
        "present": True,
        "loaded": load_ok and load_state == "loaded",
        "enabled": enabled,
        "active": active,
        "error": "" if active or enabled else (active_error or enabled_error),
    }


def set_service_enabled(
    enabled: bool, reload_daemon: bool = False, run: Any = subprocess.run,
) -> dict[str, Any]:
    """Start/enable or stop/disable the user service."""
    if reload_daemon:
        reloaded, message = _systemctl(["daemon-reload"], run)
        if not reloaded:
            return {"ok": False, "message": message or "daemon-reload failed"}

    verb = "enable" if enabled else "disable"
    ok, message = _systemctl([verb, "--now", SERVICE_NAME], run)
    return {
        "ok": ok,
        "message": message or ("Service enabled" if enabled else "Service disabled"),
    }


def synchronize_service(
    config: dict[str, Any] | None = None, run: Any = subprocess.run,
) -> dict[str, Any]:
    """Match user-service state to the current automatic-switching policy."""
    active_config = config if config is not None else audio_core.load_auto_switch_config()
    return set_service_enabled(policy_enabled(active_config), run=run)


def should_prompt_migration(config: dict[str, Any], status: dict[str, Any]) -> bool:
    """Whether an existing user should be offered persistent automation."""
    return (
        policy_enabled(config)
        and not (status.get("enabled") and status.get("active"))
        and int(config.get("service_prompt_version", 0)) < SERVICE_PROMPT_VERSION
    )


def dismiss_service_prompt(config: dict[str, Any]) -> dict[str, Any]:
    """Return a copy that records the current migration prompt version."""
    result = dict(config)
    result["service_prompt_version"] = SERVICE_PROMPT_VERSION
    return result
