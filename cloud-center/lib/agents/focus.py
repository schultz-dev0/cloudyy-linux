"""Safely correlate agent processes with Hyprland windows and focus them."""
from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

from .sessions import _agent_id


_PROC_ROOT = Path("/proc")


def _boot_time() -> int:
    for line in (_PROC_ROOT / "stat").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[0] == "btime":
            return int(fields[1])
    raise ValueError("proc stat has no boot time")


def _process_identity(pid: int, boot_time: int, clock_ticks: int) -> tuple[int, datetime]:
    value = (_PROC_ROOT / str(pid) / "stat").read_text(encoding="utf-8")
    close = value.rfind(")")
    if close < 0:
        raise ValueError("malformed process stat")
    fields = value[close + 1:].split()
    if len(fields) < 20:
        raise ValueError("malformed process stat")
    start_ticks = int(fields[19])
    if start_ticks < 0:
        raise ValueError("malformed process stat")
    started_at = datetime.fromtimestamp(
        boot_time + start_ticks / clock_ticks,
        timezone.utc,
    )
    return int(fields[1]), started_at


def _agent_identity(
    agent_id: str,
    pid: int,
    boot_time: int,
    clock_ticks: int,
) -> tuple[int, datetime]:
    initial = _process_identity(pid, boot_time, clock_ticks)
    process = _PROC_ROOT / str(pid)
    executable = os.readlink(process / "exe")
    comm = (process / "comm").read_text(encoding="utf-8")
    cmdline = (process / "cmdline").read_bytes()
    final = _process_identity(pid, boot_time, clock_ticks)
    if initial != final or _agent_id(executable, comm, cmdline) != agent_id:
        raise ValueError("agent process identity changed")
    return initial


def _walk_ancestors(
    start_pid: int,
    start: tuple[int, datetime],
    boot_time: int,
    clock_ticks: int,
) -> list[tuple[int, datetime]]:
    parent_pid, actual_start = start
    chain = [(start_pid, actual_start)]
    seen = {start_pid}
    current_pid = parent_pid
    while current_pid > 0 and current_pid not in seen:
        seen.add(current_pid)
        try:
            parent_pid, ancestor_start = _process_identity(
                current_pid, boot_time, clock_ticks,
            )
        except (OSError, OverflowError, UnicodeError, ValueError):
            break
        chain.append((current_pid, ancestor_start))
        current_pid = parent_pid
    return chain


def _tmux_client_pids(run: Callable, chain_pids: set[int]) -> list[int]:
    """Bridge a pane's shell pid to the pid of the terminal attached to its
    tmux session — tmux detaches its server from the invoking terminal, so a
    session hosted in tmux has no direct process-ancestor path to the window
    that actually owns it on screen.
    """
    try:
        panes = run(
            ["tmux", "list-panes", "-a", "-F", "#{pane_pid} #{session_name}"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if panes.returncode != 0:
            return []
        session_names = set()
        for line in panes.stdout.splitlines():
            pane_pid_text, _, session_name = line.partition(" ")
            if not session_name:
                continue
            try:
                pane_pid = int(pane_pid_text)
            except ValueError:
                continue
            if pane_pid in chain_pids:
                session_names.add(session_name)
        if not session_names:
            return []
        clients = run(
            ["tmux", "list-clients", "-F", "#{client_pid} #{client_session}"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if clients.returncode != 0:
            return []
        result = []
        for line in clients.stdout.splitlines():
            client_pid_text, _, session_name = line.partition(" ")
            if session_name not in session_names:
                continue
            try:
                result.append(int(client_pid_text))
            except ValueError:
                continue
        return result
    except (OSError, subprocess.SubprocessError):
        return []


def focus_session(
    agent_id: str,
    pid: int,
    started_at: str,
    run: Callable = subprocess.run,
) -> int:
    try:
        expected_start = datetime.fromisoformat(started_at)
        if expected_start.tzinfo is None:
            return 3
        expected_start = expected_start.astimezone(timezone.utc)
        boot_time = _boot_time()
        clock_ticks = os.sysconf("SC_CLK_TCK")
        parent_pid, actual_start = _agent_identity(
            agent_id, pid, boot_time, clock_ticks,
        )
    except (OSError, OverflowError, UnicodeError, ValueError):
        return 3
    if actual_start != expected_start:
        return 3

    chain = _walk_ancestors(pid, (parent_pid, actual_start), boot_time, clock_ticks)

    chain_pids = {candidate_pid for candidate_pid, _ in chain}
    for client_pid in _tmux_client_pids(run, chain_pids):
        if client_pid in chain_pids:
            continue
        try:
            client_start = _process_identity(client_pid, boot_time, clock_ticks)
        except (OSError, OverflowError, UnicodeError, ValueError):
            continue
        for candidate_pid, candidate_start in _walk_ancestors(
            client_pid, client_start, boot_time, clock_ticks,
        ):
            if candidate_pid in chain_pids:
                continue
            chain_pids.add(candidate_pid)
            chain.append((candidate_pid, candidate_start))

    try:
        result = run(
            ["hyprctl", "clients", "-j"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if result.returncode != 0:
            return 5
        clients = json.loads(result.stdout)
        if not isinstance(clients, list):
            return 5
    except (OSError, subprocess.SubprocessError, TypeError, ValueError):
        return 5

    addresses = {
        client["pid"]: client["address"]
        for client in clients
        if isinstance(client, dict)
        and isinstance(client.get("pid"), int)
        and isinstance(client.get("address"), str)
        and client["address"]
    }

    try:
        _, actual_start = _agent_identity(agent_id, pid, boot_time, clock_ticks)
    except (OSError, OverflowError, UnicodeError, ValueError):
        return 3
    if actual_start != expected_start:
        return 3

    address = None
    for candidate_pid, candidate_start in chain:
        if candidate_pid not in addresses:
            continue
        try:
            _, actual_start = _process_identity(candidate_pid, boot_time, clock_ticks)
        except (OSError, OverflowError, UnicodeError, ValueError):
            continue
        if actual_start == candidate_start:
            address = addresses[candidate_pid]
            break

    if address is None:
        return 4

    try:
        _, actual_start = _agent_identity(agent_id, pid, boot_time, clock_ticks)
    except (OSError, OverflowError, UnicodeError, ValueError):
        return 3
    if actual_start != expected_start:
        return 3

    try:
        result = run(
            [
                "hyprctl", "dispatch",
                f'hl.dsp.focus({{window = "address:{address}"}})',
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return 5
    return 0 if result.returncode == 0 else 5
