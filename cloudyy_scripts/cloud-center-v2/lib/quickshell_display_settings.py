"""Persist Quickshell bar/dock multi-monitor options for Cloud Center."""
from __future__ import annotations

import json
import logging
import subprocess
import sys
from pathlib import Path

from lib import utility

log = logging.getLogger(__name__)

KEY_BAR_ALL = "monitors/quickshell/bar_on_all_screens"
KEY_DOCK_ALL = "monitors/quickshell/dock_on_all_screens"

# Legacy combined JSON (migrated on first load)
_LEGACY_JSON = utility.SETTINGS_DIR / "monitors" / "quickshell.json"


def _migrate_legacy_json() -> None:
    if not _LEGACY_JSON.is_file():
        return
    try:
        data = json.loads(_LEGACY_JSON.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        log.warning("Ignoring legacy quickshell settings %s: %s", _LEGACY_JSON, exc)
        return

    if "bar_on_all_screens" in data:
        utility.save_setting(KEY_BAR_ALL, bool(data["bar_on_all_screens"]))
    if "dock_on_all_screens" in data:
        utility.save_setting(KEY_DOCK_ALL, bool(data["dock_on_all_screens"]))

    try:
        _LEGACY_JSON.unlink()
    except OSError as exc:
        log.warning("Could not remove legacy %s: %s", _LEGACY_JSON, exc)


def load() -> dict[str, bool]:
    _migrate_legacy_json()
    return {
        "bar_on_all_screens": utility.load_setting(KEY_BAR_ALL, False),
        "dock_on_all_screens": utility.load_setting(KEY_DOCK_ALL, False),
    }


def save(*, bar_on_all_screens: bool, dock_on_all_screens: bool) -> None:
    utility.save_setting(KEY_BAR_ALL, bar_on_all_screens)
    utility.save_setting(KEY_DOCK_ALL, dock_on_all_screens)


def restart_quickshell() -> tuple[bool, str]:
    """Restart Quickshell so bar/dock screen layout is rebuilt."""
    subprocess.run(
        ["quickshell", "kill"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    try:
        subprocess.Popen(
            ["sh", "-lc", "env QS_NO_RELOAD_POPUP=1 qs -d"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        return False, str(exc)
    return True, "Quickshell restarted"


def main(argv: list[str] | None = None) -> int:
    if (argv or sys.argv)[1:] == ["--restart"]:
        ok, message = restart_quickshell()
        if not ok:
            print(message, file=sys.stderr)
            return 1
        return 0
    print("Usage: quickshell_display_settings.py --restart", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
