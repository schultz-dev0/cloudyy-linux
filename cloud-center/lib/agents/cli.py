"""Expose agent usage collection, snapshots, sessions, and focus as a CLI."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, TextIO
from urllib.request import urlopen

from .collectors import claude, codex, fireworks
from .contract import load_usage_directory, write_record
from .focus import focus_session
from .sessions import scan_sessions


_PROVIDER_NAMES = {
    "claude": "Claude",
    "codex": "Codex",
    "fireworks": "Fireworks",
}


def _error_record(provider: str, now: datetime) -> dict:
    timestamp = now.isoformat()
    return {
        "schemaVersion": 1,
        "recordId": provider,
        "provider": {"id": provider, "name": _PROVIDER_NAMES[provider]},
        "planLabel": "",
        "allowances": [],
        "dataUpdatedAt": timestamp,
        "lastAttemptAt": timestamp,
        "status": {"state": "error", "message": "Collection failed"},
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="cloudyy-agents")
    commands = parser.add_subparsers(dest="command", required=True)
    collect = commands.add_parser("collect")
    collect.add_argument("--provider", choices=tuple(_PROVIDER_NAMES))
    for command in ("snapshot", "sessions"):
        output = commands.add_parser(command)
        output.add_argument("--json", action="store_true", required=True)
    focus = commands.add_parser("focus")
    focus.add_argument("--agent-id", choices=("claude", "codex", "opencode"), required=True)
    focus.add_argument("--pid", type=int, required=True)
    focus.add_argument("--started-at", required=True)
    return parser


def main(
    argv: list[str] | None = None,
    *,
    providers: dict[str, Callable[[], dict]] | None = None,
    session_scanner: Callable[[], list[dict]] = scan_sessions,
    focuser: Callable[[str, int, str], int] = focus_session,
    record_writer: Callable[[Path, dict], None] = write_record,
    now: Callable[[], datetime] | None = None,
    env: dict[str, str] | None = None,
    usage_dir: Path | None = None,
    stdout: TextIO = sys.stdout,
    stderr: TextIO = sys.stderr,
) -> int:
    args = _parser().parse_args(argv)
    current_time = (now or (lambda: datetime.now(timezone.utc)))()
    environment = os.environ if env is None else env
    if usage_dir is None:
        state_home = environment.get("XDG_STATE_HOME")
        base = Path(state_home) if state_home else Path(environment["HOME"]) / ".local/state"
        usage_dir = base / "cloudyy/agents/usage"
    if providers is None:
        providers = {
            "claude": lambda: claude.collect(current_time, urlopen, environment),
            "codex": lambda: codex.collect(current_time, subprocess.run, environment),
            "fireworks": lambda: fireworks.collect(current_time, urlopen, environment),
        }

    if args.command == "collect":
        selected = [args.provider] if args.provider else list(providers)
        failed = False
        for provider in selected:
            try:
                record = providers[provider]()
                record_writer(usage_dir / f"{provider}.json", record)
                if record.get("status", {}).get("state") == "error":
                    failed = True
            except Exception:
                failed = True
                try:
                    record_writer(
                        usage_dir / f"{provider}.json",
                        _error_record(provider, current_time),
                    )
                except Exception:
                    pass
        return 1 if failed else 0

    if args.command == "sessions":
        json.dump(session_scanner(), stdout, separators=(",", ":"))
        stdout.write("\n")
        return 0

    if args.command == "snapshot":
        json.dump({
            "usage": load_usage_directory(usage_dir, current_time),
            "sessions": session_scanner(),
        }, stdout, separators=(",", ":"))
        stdout.write("\n")
        return 0

    return focuser(args.agent_id, args.pid, args.started_at)


if __name__ == "__main__":
    raise SystemExit(main())
