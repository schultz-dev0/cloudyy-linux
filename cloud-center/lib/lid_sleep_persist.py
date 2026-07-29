"""
Cloud Center — lib/lid_sleep_persist.py
Toggles laptop lid-close suspend without root: while the cloudyy-lid-inhibit
user service is active it holds a systemd-logind handle-lid-switch inhibitor
lock, so closing the lid keeps the session running. Disabling the service
hands the lid back to logind's default (suspend).
"""
from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from pathlib import Path

log = logging.getLogger(__name__)

UNIT_DIR = Path.home() / ".config" / "systemd" / "user"
UNIT_NAME = "cloudyy-lid-inhibit.service"

_UNIT_CONTENT = """\
[Unit]
Description=Block logind lid-switch suspend (Cloud Center)

[Service]
ExecStart=/usr/bin/systemd-inhibit --what=handle-lid-switch --who=cloudyy --why="Lid suspend disabled in Cloud Center" --mode=block /usr/bin/sleep infinity
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
"""


def _run(*args: str) -> None:
    result = subprocess.run(
        ["systemctl", "--user", *args],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown error").strip()
        raise RuntimeError(f"systemctl --user {args[0]} failed: {detail}")


def _ensure_unit() -> None:
    path = UNIT_DIR / UNIT_NAME
    if path.exists():
        return
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(_UNIT_CONTENT, encoding="utf-8")
    _run("daemon-reload")


def set_lid_sleep_enabled(enabled: bool) -> bool:
    _ensure_unit()
    # Sleep allowed -> no inhibitor; sleep disabled -> hold the lid-switch lock.
    _run("disable" if enabled else "enable", "--now", UNIT_NAME)
    return enabled


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="lid_sleep_persist")
    parser.add_argument("state", choices=["on", "off"])
    args = parser.parse_args(argv)

    try:
        payload = {"ok": True, "enabled": set_lid_sleep_enabled(args.state == "on")}
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1

    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
