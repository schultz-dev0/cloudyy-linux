#!/usr/bin/env python3
"""Read Cursor's recent workspace list without mutating its state database."""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
from pathlib import Path
from typing import Callable
from urllib.parse import unquote, urlparse


RECENT_KEY = "history.recentlyOpenedPathsList"


def default_db() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "Cursor/User/globalStorage/state.vscdb"


def _local_path(uri: str) -> Path | None:
    parsed = urlparse(uri)
    if parsed.scheme != "file":
        return None
    return Path(unquote(parsed.path))


def read_recent_workspaces(
    db_path: Path,
    path_exists: Callable[[Path], bool] = Path.exists,
) -> list[str]:
    db_path = Path(db_path)
    if not db_path.is_file():
        return []

    try:
        connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            row = connection.execute(
                "SELECT value FROM ItemTable WHERE key = ?", (RECENT_KEY,)
            ).fetchone()
        finally:
            connection.close()
    except sqlite3.Error:
        return []

    if not row or not isinstance(row[0], str):
        return []
    try:
        payload = json.loads(row[0])
    except (TypeError, ValueError):
        return []

    entries = payload.get("entries", []) if isinstance(payload, dict) else []
    result: list[str] = []
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        uri = entry.get("folderUri") or entry.get("workspaceUri")
        if not isinstance(uri, str) or not uri.strip():
            continue
        uri = uri.strip()
        parsed = urlparse(uri)
        if not parsed.scheme:
            continue
        local_path = _local_path(uri)
        if local_path is not None and not path_exists(local_path):
            continue
        if uri not in seen:
            seen.add(uri)
            result.append(uri)
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--db", type=Path, default=default_db())
    args = parser.parse_args(argv)

    if args.command == "list":
        print(json.dumps({"workspaces": read_recent_workspaces(args.db)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
