"""
Cloud Center — lib/ccd/state.py
Page subscriptions: watches stateful items (toggles with a state_command,
labels with a value source) and pushes events only when something changes.

The frontend subscribes when a page becomes visible and unsubscribes when it
goes away, so nothing is watched for pages the user isn't looking at.
"""
from __future__ import annotations

import logging
import subprocess
import threading
from dataclasses import dataclass, field
from typing import Callable

import lib.utility as utility
from lib.ccd import actions, model, protocol

log = logging.getLogger(__name__)

# state_command outputs that count as "on" (ported from the GTK toggle rows).
TRUTHY_OUTPUTS = {"yes", "true", "1", "on", "enabled", "active", "running"}

STATE_TIMEOUT = 5      # seconds one state/label command may take
DEFAULT_INTERVAL = 5   # seconds between checks when the YAML gives none

# Live watchers by page id. THE registry — subscribe fills it, unsubscribe
# empties it, shutdown() clears everything.
ACTIVE: dict[str, list["Watcher"]] = {}

# Setting-key → factory overrides for event-driven sources (nmcli monitor,
# bluetoothctl, ...). watchers.py registers entries; polling is the fallback.
KEY_WATCHER_FACTORIES: dict[str, Callable[[str, dict], "Watcher"]] = {}

UNSET = object()


@dataclass
class Watcher:
    item_id: str
    check: Callable[[], None]          # one check; sends an event on change
    interval: float                    # <= 0 means run once, no loop
    stop: threading.Event = field(default_factory=threading.Event)
    thread: threading.Thread | None = None
    last: object = UNSET
    # Event-driven watchers set these instead of relying on the poll loop:
    run: Callable[["Watcher"], None] | None = None
    process: subprocess.Popen | None = None


def parse_truthy(output: str) -> bool:
    out = output.strip().lower()
    return out in TRUTHY_OUTPUTS or (out.isdigit() and int(out) > 0)


def run_state_command(cmd: str) -> bool | None:
    """Run a state_command and parse its output; None if it failed."""
    try:
        result = subprocess.run(
            ["bash", "-c", cmd],
            env=utility.command_env(),
            capture_output=True,
            text=True,
            timeout=STATE_TIMEOUT,
        )
        return parse_truthy(result.stdout)
    except Exception as exc:
        log.warning("state_command failed (%s): %s", cmd, exc)
        return None


def send_state(watcher: Watcher, key: str, value: bool) -> None:
    """Push a state event if the value actually changed."""
    if value == watcher.last:
        return
    watcher.last = value
    protocol.send_event(
        {"event": "state", "item": watcher.item_id, "key": key, "value": value}
    )


def label_text(value_cfg: dict) -> str:
    match value_cfg.get("type", ""):
        case "system":
            return utility.get_system_info(value_cfg.get("key", ""))
        case "exec":
            try:
                result = subprocess.run(
                    ["bash", "-c", value_cfg.get("command", "")],
                    env=utility.command_env(),
                    capture_output=True,
                    text=True,
                    timeout=STATE_TIMEOUT,
                )
                return result.stdout.strip() or "N/A"
            except Exception:
                return "Error"
        case "static":
            return str(value_cfg.get("text", ""))
    return ""


# ── Watcher construction ─────────────────────────────────────────────────────


def make_toggle_watcher(item_id: str, raw: dict) -> Watcher:
    props = raw.get("properties", {}) or {}
    key = props.get("key", "")
    state_cmd = props.get("state_command", "")
    interval = float(props.get("interval", DEFAULT_INTERVAL))

    watcher = Watcher(item_id=item_id, check=lambda: None, interval=interval)

    def check() -> None:
        value = run_state_command(state_cmd)
        if value is not None:
            send_state(watcher, key, value)

    watcher.check = check
    return watcher


def make_label_watcher(item_id: str, raw: dict) -> Watcher:
    props = raw.get("properties", {}) or {}
    value_cfg = raw.get("value", {}) or {}
    interval = float(props.get("interval", 0))

    watcher = Watcher(item_id=item_id, check=lambda: None, interval=interval)

    def check() -> None:
        text = label_text(value_cfg)
        if text == watcher.last:
            return
        watcher.last = text
        protocol.send_event({"event": "label", "item": item_id, "text": text})

    watcher.check = check
    return watcher


def make_wallpaper_watcher(item_id: str, raw: dict) -> Watcher:
    """Re-list the transitional wallpaper pool when active theme mode changes."""
    props = raw.get("properties", {}) or {}
    directory = props.get("directory", "")
    max_items = int(props.get("max_items", 100))
    interval = float(props.get("interval", DEFAULT_INTERVAL))

    watcher = Watcher(item_id=item_id, check=lambda: None, interval=interval)

    def check() -> None:
        try:
            mode = model.theme_mode()
        except RuntimeError:
            return
        if mode == watcher.last:
            return
        watcher.last = mode
        wallpapers = model.wallpaper_list(directory, max_items)
        protocol.send_event(
            {"event": "wallpapers", "item": item_id, "wallpapers": wallpapers}
        )

    watcher.check = check
    return watcher


def make_watcher(item_id: str, raw: dict) -> Watcher | None:
    """Build the right watcher for one item, or None if it has no state."""
    props = raw.get("properties", {}) or {}
    match raw.get("type", ""):
        case "toggle" if props.get("state_command"):
            key = props.get("key", "")
            factory = KEY_WATCHER_FACTORIES.get(key)
            if factory is not None:
                return factory(item_id, raw)
            return make_toggle_watcher(item_id, raw)
        case "label" if raw.get("value"):
            return make_label_watcher(item_id, raw)
        case "wallpaper_picker":
            return make_wallpaper_watcher(item_id, raw)
    return None


# ── Watcher lifecycle ─────────────────────────────────────────────────────────


def poll_loop(watcher: Watcher) -> None:
    while not watcher.stop.is_set():
        watcher.check()
        if watcher.interval <= 0:
            return
        watcher.stop.wait(watcher.interval)


def start_watcher(watcher: Watcher) -> None:
    target = watcher.run if watcher.run is not None else poll_loop
    watcher.thread = threading.Thread(target=target, args=(watcher,), daemon=True)
    watcher.thread.start()


def stop_watcher(watcher: Watcher) -> None:
    watcher.stop.set()
    if watcher.process is not None and watcher.process.poll() is None:
        watcher.process.terminate()


def subscribe(params: dict) -> dict:
    page = params.get("page", "")
    if page in ACTIVE:
        return {"watchers": len(ACTIVE[page])}

    watchers = []
    prefix = f"{page}/"
    for item_id, raw in model.ITEMS.items():
        if not item_id.startswith(prefix):
            continue
        watcher = make_watcher(item_id, raw)
        if watcher is not None:
            watchers.append(watcher)

    ACTIVE[page] = watchers
    for watcher in watchers:
        start_watcher(watcher)
    return {"watchers": len(watchers)}


def unsubscribe(params: dict) -> dict:
    page = params.get("page", "")
    watchers = ACTIVE.pop(page, [])
    for watcher in watchers:
        stop_watcher(watcher)
    return {"stopped": len(watchers)}


def shutdown() -> None:
    """Stop everything (stdin closed / process exiting)."""
    for page in list(ACTIVE):
        unsubscribe({"page": page})


def recheck_after_action(item_id: str) -> None:
    """Confirm an item's real state right after its action ran.

    last is reset so the check always emits — a failed command leaves real
    state unchanged, and change-suppression would otherwise swallow the
    event the UI needs to correct its optimistic flip. Stream watchers
    (bluetoothctl etc.) have a one-shot check() too, so they recheck as well.
    """
    for watchers in ACTIVE.values():
        for watcher in watchers:
            if watcher.item_id == item_id:
                watcher.last = UNSET
                threading.Thread(target=watcher.check, daemon=True).start()


actions.AFTER_ACTION_HOOKS.append(recheck_after_action)
protocol.register("subscribe", subscribe)
protocol.register("unsubscribe", unsubscribe)
