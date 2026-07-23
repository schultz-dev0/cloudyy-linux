#!/usr/bin/env python3
"""Return Hyprland clients with conservative process application keys."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


GENERIC_EXECUTABLES = {
    "bash",
    "env",
    "sh",
    "uwsm-app",
}


def _normalized_basename(path: str) -> str:
    return Path(path).name.strip().lower()


def _is_generic(executable: str) -> bool:
    name = _normalized_basename(executable)
    return (
        name in GENERIC_EXECUTABLES
        or name.startswith("electron")
        or name.startswith("python")
    )


def process_app_key(exe: str, cmdline: list[str]) -> str:
    for argument in cmdline:
        normalized = str(argument).replace("\\", "/")
        match = re.search(r"/([^/]+)/resources/app(?:/|$)", normalized, re.IGNORECASE)
        if match:
            return match.group(1).strip().lower()

    if not exe or _is_generic(exe):
        return ""
    name = _normalized_basename(exe)
    return re.sub(r"[^a-z0-9._-]+", "-", name).strip("-")


def _read_process(pid: int, proc_root: Path) -> tuple[str, list[str]]:
    process_dir = proc_root / str(pid)
    exe = os.readlink(process_dir / "exe")
    raw = (process_dir / "cmdline").read_bytes()
    cmdline = [
        part.decode("utf-8", errors="replace")
        for part in raw.split(b"\0")
        if part
    ]
    return exe, cmdline


def enrich_clients(clients: list[dict[str, Any]], proc_root: Path = Path("/proc")) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for client in clients:
        copy = dict(client)
        try:
            pid = int(client.get("pid", 0))
            if pid <= 0:
                raise ValueError("missing pid")
            exe, cmdline = _read_process(pid, proc_root)
            key = process_app_key(exe, cmdline)
            if key:
                copy["processAppKey"] = key
        except (OSError, TypeError, ValueError):
            pass
        enriched.append(copy)
    return enriched


def main() -> int:
    try:
        completed = subprocess.run(
            ["hyprctl", "clients", "-j"],
            check=True,
            capture_output=True,
            text=True,
        )
        clients = json.loads(completed.stdout)
        if not isinstance(clients, list):
            clients = []
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
        clients = []
    print(json.dumps(enrich_clients(clients)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
