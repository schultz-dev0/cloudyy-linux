"""
Cloud Center — lib/hypridle_persist.py
Persists idle timing controls into ~/.config/hypr/hypridle.conf, then restarts
hypridle so the new scene/lock timeouts take effect immediately. The rain
scene and the secure-lock listener can each be disabled independently.
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

log = logging.getLogger(__name__)

HYPRIDLE_CONF = Path.home() / ".config" / "hypr" / "hypridle.conf"

_SCENE_COMMAND = "cloudyy-idle show"
_SCENE_DISABLED_COMMAND = "true"
_SCENE_RESUME_COMMAND = "cloudyy-idle dismiss"
_LOCK_COMMAND = "cloudyy-lock"
# Unlike the scene listener, the lock listener has no on-resume marker that
# survives disabling, so the disabled command keeps "cloudyy-lock" in a
# trailing comment — _find_listener does substring matching, so the listener
# stays findable (and sh treats it as a comment if hypridle execs it).
_LOCK_DISABLED_COMMAND = "true # cloudyy-lock"

_TARGET_MARKERS = {
    "scene": (_SCENE_COMMAND, _SCENE_RESUME_COMMAND),
    "lock": (_LOCK_COMMAND,),
}
_TIMEOUT_RE = re.compile(r"^(?P<indent>\s*)timeout\s*=")
_ON_TIMEOUT_RE = re.compile(r"^(?P<indent>\s*)on-timeout\s*=")


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    Path(tmp_path).replace(path)


def _seconds(minutes: str) -> int:
    value = float(minutes)
    if value <= 0:
        raise ValueError("idle timeout must be greater than zero minutes")
    return int(round(value * 60))


def _find_listener(lines: list[str], markers: tuple[str, ...]) -> tuple[int, int]:
    i = 0
    while i < len(lines):
        if lines[i].strip() != "listener {":
            i += 1
            continue

        start = i
        end = i + 1
        while end < len(lines) and lines[end].strip() != "}":
            end += 1
        if end >= len(lines):
            raise ValueError("hypridle.conf has an unclosed listener block")

        block = lines[start:end + 1]
        if any(marker in line for marker in markers for line in block):
            return start, end

        i = end + 1

    raise ValueError(f"no hypridle listener found for {markers[0]}")


def _set_timeout(lines: list[str], target: str, seconds: int) -> list[str]:
    markers = _TARGET_MARKERS.get(target)
    if markers is None:
        raise ValueError(f"unsupported idle timeout target '{target}'")

    start, end = _find_listener(lines, markers)
    for idx in range(start, end + 1):
        match = _TIMEOUT_RE.match(lines[idx])
        if match:
            lines[idx] = f"{match.group('indent')}timeout = {seconds}"
            return lines
    raise ValueError(f"hypridle listener for {markers[0]} has no timeout line")


def _set_on_timeout_command(lines: list[str], target: str, command: str) -> list[str]:
    start, end = _find_listener(lines, _TARGET_MARKERS[target])
    for idx in range(start, end + 1):
        match = _ON_TIMEOUT_RE.match(lines[idx])
        if match:
            lines[idx] = f"{match.group('indent')}on-timeout = {command}"
            return lines
    raise ValueError(f"hypridle {target} listener has no on-timeout line")


def _restart_hypridle() -> None:
    result = subprocess.run(
        ["systemctl", "--user", "reset-failed", "hypridle.service"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown error").strip()
        raise RuntimeError(f"could not reset failed hypridle state: {detail}")

    result = subprocess.run(
        ["systemctl", "--user", "restart", "hypridle.service"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown error").strip()
        raise RuntimeError(f"could not restart hypridle.service: {detail}")


def apply(target: str, minutes: str, *, restart: bool = True) -> int:
    seconds = _seconds(minutes)
    path = HYPRIDLE_CONF
    lines = path.read_text(encoding="utf-8").splitlines()
    updated = _set_timeout(lines, target, seconds)
    _atomic_write(path, "\n".join(updated).rstrip("\n") + "\n")

    if restart:
        _restart_hypridle()
    return seconds


def set_scene_enabled(enabled: bool, *, restart: bool = True) -> bool:
    command = _SCENE_COMMAND if enabled else _SCENE_DISABLED_COMMAND
    path = HYPRIDLE_CONF
    lines = path.read_text(encoding="utf-8").splitlines()
    updated = _set_on_timeout_command(lines, "scene", command)
    _atomic_write(path, "\n".join(updated).rstrip("\n") + "\n")

    if restart:
        _restart_hypridle()
    return enabled


def set_lock_enabled(enabled: bool, *, restart: bool = True) -> bool:
    command = _LOCK_COMMAND if enabled else _LOCK_DISABLED_COMMAND
    path = HYPRIDLE_CONF
    lines = path.read_text(encoding="utf-8").splitlines()
    updated = _set_on_timeout_command(lines, "lock", command)
    _atomic_write(path, "\n".join(updated).rstrip("\n") + "\n")

    if restart:
        _restart_hypridle()
    return enabled


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hypridle_persist")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_apply = sub.add_parser("apply")
    p_apply.add_argument("target", choices=sorted(_TARGET_MARKERS))
    p_apply.add_argument("minutes")

    p_scene = sub.add_parser("scene")
    p_scene.add_argument("state", choices=["on", "off"])

    p_lock = sub.add_parser("lock")
    p_lock.add_argument("state", choices=["on", "off"])

    args = parser.parse_args(argv)

    try:
        if args.cmd == "apply":
            payload = {"ok": True, "seconds": apply(args.target, args.minutes)}
        elif args.cmd == "scene":
            payload = {"ok": True, "enabled": set_scene_enabled(args.state == "on")}
        else:
            payload = {"ok": True, "enabled": set_lock_enabled(args.state == "on")}
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1

    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
