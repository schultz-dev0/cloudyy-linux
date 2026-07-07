"""
Cloud Center — lib/ccd/watchers.py
Event-driven state sources that replace polling for specific setting keys.

`bluetoothctl` held open on a pipe emits "[CHG] Controller ... Powered: yes/no"
lines, so Bluetooth state arrives the moment it changes. Wi-Fi stays on the
generic polling watcher: `nmcli monitor` emits no radio-state lines
(verified 2026-07-07), so there is no stream to parse.

A missing binary falls back to the generic polling watcher.
"""
from __future__ import annotations

import logging
import re
import shutil
import subprocess
from typing import Callable

import lib.utility as utility
from lib.ccd import state

log = logging.getLogger(__name__)

ANSI_CODES = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

BLUETOOTHCTL = "bluetoothctl"


def parse_bluetoothctl_line(line: str) -> bool | None:
    """'[CHG] Controller XX Powered: yes/no' → bool; anything else → None."""
    text = ANSI_CODES.sub("", line)
    if "Controller" not in text or "Powered:" not in text:
        return None
    return text.rsplit("Powered:", 1)[1].strip().lower() == "yes"


def make_stream_watcher(
    item_id: str,
    raw: dict,
    argv: list[str],
    parse_line: Callable[[str], bool | None],
) -> state.Watcher:
    """A watcher fed by a long-running process's stdout instead of polling."""
    props = raw.get("properties", {}) or {}
    key = props.get("key", "")
    state_cmd = props.get("state_command", "")

    watcher = state.Watcher(item_id=item_id, check=lambda: None, interval=0)

    def check() -> None:
        """One-shot state read for the initial value and action rechecks."""
        if state_cmd:
            value = state.run_state_command(state_cmd)
            if value is not None:
                state.send_state(watcher, key, value)

    def run(watcher: state.Watcher) -> None:
        check()
        try:
            process = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE,  # held open; bluetoothctl exits on EOF
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                env=utility.command_env(),
            )
        except OSError as exc:
            log.warning("stream watcher %s failed to start: %s", argv[0], exc)
            return
        watcher.process = process
        for line in process.stdout:
            if watcher.stop.is_set():
                break
            value = parse_line(line)
            if value is not None:
                state.send_state(watcher, key, value)
        if process.poll() is None:
            process.terminate()

    watcher.check = check
    watcher.run = run
    return watcher


def make_bluetooth_watcher(item_id: str, raw: dict) -> state.Watcher:
    if shutil.which(BLUETOOTHCTL) is None:
        return state.make_toggle_watcher(item_id, raw)
    return make_stream_watcher(item_id, raw, [BLUETOOTHCTL], parse_bluetoothctl_line)


# Setting keys with an event-driven source. state.make_watcher consults this
# via KEY_WATCHER_FACTORIES; anything not listed polls its YAML state_command.
WATCHERS: dict[str, Callable[[str, dict], state.Watcher]] = {
    "hypr/bluetooth": make_bluetooth_watcher,
}

state.KEY_WATCHER_FACTORIES.update(WATCHERS)
