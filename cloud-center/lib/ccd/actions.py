"""
Cloud Center — lib/ccd/actions.py
Executes row actions: shell commands with the same template semantics as the
GTK rows, settings persistence, and completion events.

Commands run in worker threads; when one finishes, an "action_done" event is
pushed (plus a "toast" event on failure) so the frontend never blocks.
"""
from __future__ import annotations

import logging
import subprocess
import threading
from typing import Callable

import lib.utility as utility
from lib.ccd import model, protocol

log = logging.getLogger(__name__)

COMMAND_TIMEOUT = 60  # seconds, same as the GTK app

# Called with the item id after its command finishes. state.py registers a
# watcher recheck here so toggles confirm their real state immediately.
AFTER_ACTION_HOOKS: list[Callable[[str], None]] = []


class UnknownItemError(Exception):
    pass


def compact_number(value: float) -> str:
    """12.0 -> '12', 0.550 -> '0.55' (matches the GTK slider formatting)."""
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.3f}".rstrip("0").rstrip(".")


def mapped_text(mapped) -> str:
    """YAML options_map values may be bools; commands need 'true'/'false'."""
    if isinstance(mapped, bool):
        return "true" if mapped else "false"
    return str(mapped)


def substitute(template: str, value, mapped=None) -> str:
    """
    The one definition of command template semantics.

    Numeric value (sliders): {value} compact, {value_i} rounded int,
    {value_f} two decimals. String value (selections): {value} is the mapped
    text, {option} is the raw option name.
    """
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return (
            template
            .replace("{value}", compact_number(value))
            .replace("{value_i}", str(int(round(value))))
            .replace("{value_f}", f"{value:.2f}")
        )
    if mapped is None:
        mapped = value
    return (
        template
        .replace("{value}", mapped_text(mapped))
        .replace("{option}", str(value))
    )


def run_command(cmd: str, item_id: str, terminal: bool = False) -> None:
    """Run one shell command in a worker thread and report when it's done."""
    expanded = utility.expand_command(cmd)
    argv = (
        ["kitty", "--", "bash", "-c", expanded]
        if terminal
        else ["bash", "-c", expanded]
    )

    def worker() -> None:
        ok, detail = True, ""
        try:
            result = subprocess.run(
                argv,
                env=utility.command_env(),
                capture_output=True,
                text=True,
                timeout=COMMAND_TIMEOUT,
            )
            if result.returncode != 0:
                ok = False
                detail = (
                    result.stderr or result.stdout or f"exit {result.returncode}"
                ).strip()
        except Exception as exc:
            ok, detail = False, str(exc)

        if not ok:
            log.error("command failed: %s\n  cmd: %s", detail, cmd)
            protocol.send_event(
                {"event": "toast", "text": f"Command failed: {detail[:120]}"}
            )
        protocol.send_event({"event": "action_done", "item": item_id, "ok": ok})
        for hook in AFTER_ACTION_HOOKS:
            hook(item_id)

    threading.Thread(target=worker, daemon=True).start()


def run_action(params: dict) -> dict:
    """Execute the action belonging to one model item."""
    item_id = params.get("item", "")
    raw = model.ITEMS.get(item_id)
    if raw is None:
        raise UnknownItemError(f"unknown item: {item_id}")

    props = raw.get("properties", {}) or {}
    key = props.get("key", "")
    item_type = raw.get("type", "")

    match item_type:
        case "button":
            action_id = props.get("action", "")
            if action_id.startswith("navigate_page:"):
                return {"navigate": action_id.split(":", 1)[1].strip()}
            if action_id:
                # Built-in UI actions (e.g. bezier_editor); frontend opens a dialog.
                return {"open": action_id, "builtin": action_id}
            press = raw.get("on_press") or {}
            if cmd := press.get("command", ""):
                run_command(cmd, item_id, terminal=bool(press.get("terminal", False)))
            return {"started": True}

        case "toggle":
            value = bool(params.get("value"))
            if key:
                utility.save_setting(key, value)
            branches = raw.get("on_toggle") or {}
            branch = branches.get("enabled" if value else "disabled") or {}
            if cmd := branch.get("command", ""):
                run_command(cmd, item_id, terminal=bool(branch.get("terminal", False)))
            return {"started": True}

        case "slider":
            value = float(params.get("value", 0))
            if key:
                utility.save_setting(key, value)
            change = raw.get("on_change") or {}
            if cmd := change.get("command", ""):
                run_command(substitute(cmd, value), item_id)
            return {"started": True}

        case "selection":
            value = str(params.get("value", ""))
            options_map = props.get("options_map") or {}
            if key:
                utility.save_setting(key, value)
            change = raw.get("on_change") or {}
            if cmd := change.get("command", ""):
                run_command(
                    substitute(cmd, value, options_map.get(value, value)), item_id
                )
            return {"started": True}

        case "multi_selection":
            values = [str(v) for v in params.get("values", [])]
            options_map = props.get("options_map") or {}
            joined = ",".join(values)
            mapped_joined = ",".join(
                mapped_text(options_map.get(v, v)) for v in values
            )
            if key:
                utility.save_setting(key, joined)
            change = raw.get("on_change") or {}
            if cmd := change.get("command", ""):
                run_command(substitute(cmd, joined, mapped_joined), item_id)
            return {"started": True}

        case "wallpaper_picker":
            path = str(params.get("path", ""))
            if key:
                utility.save_setting(key, path)
            select = raw.get("on_select") or {}
            if cmd := select.get("command", ""):
                run_command(cmd.replace("{path}", path), item_id)
            return {"started": True}

    raise UnknownItemError(f"item {item_id} ({item_type}) has no runnable action")


def set_setting(params: dict) -> bool:
    return utility.save_setting(params.get("key", ""), params.get("value"))


def get_setting(params: dict):
    return utility.load_setting(params.get("key", ""), params.get("default"))


protocol.register("run_action", run_action)
protocol.register("set_setting", set_setting)
protocol.register("get_setting", get_setting)
