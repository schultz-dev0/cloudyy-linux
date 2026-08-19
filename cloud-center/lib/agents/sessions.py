"""Discover live Claude, Codex, and OpenCode sessions from procfs."""
from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path


_AGENTS = {
    "claude": "Claude",
    "codex": "Codex",
    "opencode": "OpenCode",
}


def _boot_time(proc_root: Path) -> int:
    for line in (proc_root / "stat").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[0] == "btime":
            return int(fields[1])
    raise ValueError("proc stat has no boot time")


def _process_stat(value: str) -> tuple[int, int]:
    close = value.rfind(")")
    if close < 0:
        raise ValueError("malformed process stat")
    fields = value[close + 1:].split()
    if len(fields) < 20:
        raise ValueError("malformed process stat")
    start_ticks = int(fields[19])
    if start_ticks < 0:
        raise ValueError("malformed process stat")
    return int(fields[1]), start_ticks


def _agent_id(executable: str, comm: str, cmdline: bytes) -> str | None:
    argv0 = cmdline.split(b"\0", 1)[0].decode("utf-8")
    matched = None
    for value in (Path(executable).name, comm.strip(), Path(argv0).name):
        if value in _AGENTS:
            matched = value
            break
    if matched is None:
        return None
    # Two known false positives, not a live coding session:
    # - the desktop app (different binary, e.g. claude-desktop-bin)
    # - an agent's own internal background helper ("<bin> daemon run ...")
    if "claude-desktop-bin" in Path(executable).parts:
        return None
    args = [part for part in cmdline.split(b"\0") if part]
    if len(args) >= 2 and args[1] == b"daemon":
        return None
    return matched


def scan_sessions(
    proc_root: Path = Path("/proc"),
    now: datetime | None = None,
) -> list[dict]:
    del now
    try:
        boot_time = _boot_time(proc_root)
        clock_ticks = os.sysconf("SC_CLK_TCK")
        entries = list(proc_root.iterdir())
    except (OSError, UnicodeError, ValueError):
        return []

    processes = []
    for entry in entries:
        if not entry.name.isdecimal():
            continue
        try:
            pid = int(entry.name)
            initial_stat = _process_stat(
                (entry / "stat").read_text(encoding="utf-8"),
            )
            executable = os.readlink(entry / "exe")
            comm = (entry / "comm").read_text(encoding="utf-8")
            cmdline = (entry / "cmdline").read_bytes()
            agent_id = _agent_id(executable, comm, cmdline)
            working_directory = os.readlink(entry / "cwd") if agent_id else None
            final_stat = _process_stat(
                (entry / "stat").read_text(encoding="utf-8"),
            )
            if final_stat != initial_stat:
                continue
        except (OSError, OverflowError, UnicodeError, ValueError):
            continue

        parent_pid, start_ticks = initial_stat
        processes.append({
            "agentId": agent_id,
            "pid": pid,
            "parentPid": parent_pid,
            "workingDirectory": working_directory,
            "startTicks": start_ticks,
        })

    by_pid = {process["pid"]: process for process in processes}
    sessions = []
    for process in processes:
        if process["agentId"] is None:
            continue
        chain = []
        seen = set()
        current = process
        while current is not None and current["pid"] not in seen:
            seen.add(current["pid"])
            if current["agentId"] is not None:
                chain.append(current)
            current = by_pid.get(current["parentPid"])
        oldest = min(chain, key=lambda item: (item["startTicks"], item["pid"]))
        if oldest["pid"] != process["pid"]:
            continue
        try:
            started_at = datetime.fromtimestamp(
                boot_time + process["startTicks"] / clock_ticks,
                timezone.utc,
            ).isoformat()
        except (OverflowError, OSError, ValueError):
            continue
        sessions.append({
            "agentId": process["agentId"],
            "agentName": _AGENTS[process["agentId"]],
            "pid": process["pid"],
            "workingDirectory": process["workingDirectory"],
            "projectName": Path(process["workingDirectory"]).name,
            "startedAt": started_at,
            "state": "running",
        })

    sessions.sort(key=lambda session: (session["startedAt"], session["pid"]))
    return sessions
