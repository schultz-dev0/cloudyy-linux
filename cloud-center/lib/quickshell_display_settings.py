"""Quickshell settings for Cloud Center (display layout + launch performance)."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from pathlib import Path

from lib import utility

log = logging.getLogger(__name__)

KEY_BAR_ALL = "monitors/quickshell/bar_on_all_screens"
KEY_DOCK_ALL = "monitors/quickshell/dock_on_all_screens"
KEY_LIGHTWEIGHT = "quickshell/lightweight"

_LEGACY_JSON = utility.SETTINGS_DIR / "monitors" / "quickshell.json"
_QS_ENV_FILE = Path.home() / ".config" / "quickshell" / "qs.env"


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


def lightweight_enabled() -> bool:
    return utility.load_setting(KEY_LIGHTWEIGHT, False)


def launch_env() -> dict[str, str]:
    """Environment for qs / quickshell (includes Cloud Center performance flags)."""
    env = os.environ.copy()
    env["QS_NO_RELOAD_POPUP"] = "1"
    if lightweight_enabled():
        env["CLOUDYY_LIGHTWEIGHT"] = "1"
    else:
        env.pop("CLOUDYY_LIGHTWEIGHT", None)
    return env


def load() -> dict[str, bool]:
    _migrate_legacy_json()
    return {
        "bar_on_all_screens": utility.load_setting(KEY_BAR_ALL, False),
        "dock_on_all_screens": utility.load_setting(KEY_DOCK_ALL, False),
        "lightweight": lightweight_enabled(),
    }


def save(*, bar_on_all_screens: bool, dock_on_all_screens: bool) -> None:
    utility.save_setting(KEY_BAR_ALL, bar_on_all_screens)
    utility.save_setting(KEY_DOCK_ALL, dock_on_all_screens)


def _write_env_file() -> None:
    lines = []
    if lightweight_enabled():
        lines.append("CLOUDYY_LIGHTWEIGHT=1")
    try:
        _QS_ENV_FILE.parent.mkdir(parents=True, exist_ok=True)
        _QS_ENV_FILE.write_text("\n".join(lines) + "\n" if lines else "", encoding="utf-8")
    except OSError as exc:
        log.warning("Could not write QS env file %s: %s", _QS_ENV_FILE, exc)


def _systemctl(*args: str, timeout: int = 5) -> bool:
    result = subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        timeout=timeout,
    )
    return result.returncode == 0


def kill_quickshell() -> None:
    if _systemctl("stop", "quickshell.service"):
        return
    subprocess.run(["quickshell", "kill"], capture_output=True, text=True, timeout=5)
    subprocess.run(["killall", "-9", "quickshell"], capture_output=True, timeout=3)
    subprocess.run(["killall", "-9", "qs"], capture_output=True, timeout=3)


def start_daemon(extra_args: list[str] | None = None) -> tuple[bool, str]:
    if not extra_args and _systemctl("start", "quickshell.service"):
        return True, "Quickshell started"
    cmd = ["qs", *(extra_args or ["-n", "-d"])]
    try:
        subprocess.Popen(
            cmd,
            env=launch_env(),
            cwd=os.path.expanduser("~"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        return False, str(exc)
    return True, "Quickshell started"


def restart_quickshell() -> tuple[bool, str]:
    _write_env_file()
    if _systemctl("restart", "quickshell.service", timeout=10):
        return True, "Quickshell restarted"
    kill_quickshell()
    return start_daemon()


def main(argv: list[str] | None = None) -> int:
    args = (argv or sys.argv)[1:]
    if args == ["--restart"]:
        ok, message = restart_quickshell()
        if not ok:
            print(message, file=sys.stderr)
            return 1
        return 0
    if args == ["--daemon"]:
        ok, message = start_daemon()
        if not ok:
            print(message, file=sys.stderr)
            return 1
        return 0
    print(
        "Usage: quickshell_display_settings.py --restart | --daemon",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
