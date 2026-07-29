"""
Cloud Center — lib/ccd/keybinds.py
QML-facing wrapper around lib/keybind_manager_lua.py's module-level Lua
parsing/writing functions (those are plain functions, no GTK coupling — only
the dialog/page classes further down that file are GTK-specific, so this
module reuses scan_keybinds/add_keybind/update_keybind/remove_keybind/
adopt_keybind directly instead of re-implementing Lua parsing).
"""
from __future__ import annotations

import logging
import subprocess

import lib.keybind_manager_lua as kbm
from lib.ccd import protocol

log = logging.getLogger(__name__)

CATEGORIES = [{"id": cid, "label": label} for cid, (label, _icon) in kbm.CATEGORY_META.items()]


def _entry_dict(e: kbm.LuaKeybindEntry) -> dict:
    return {
        "keys": e.keys,
        "dispatcher": e.dispatcher,
        "opts": e.opts,
        "owned": e.owned,
        "source_name": e.source_name,
        "category": kbm._categorize_dispatcher(e.dispatcher),
    }


def list_keybinds(params: dict) -> dict:
    return {
        "keybinds": [_entry_dict(e) for e in kbm.scan_keybinds()],
        "categories": CATEGORIES,
    }


def _entry_from(params: dict, prefix: str = "") -> kbm.LuaKeybindEntry:
    return kbm.LuaKeybindEntry(
        keys=str(params.get(f"{prefix}keys", "")),
        dispatcher=str(params.get(f"{prefix}dispatcher", "")),
        opts=str(params.get(f"{prefix}opts", "")),
        raw_line="",
        owned=bool(params.get(f"{prefix}owned", True)),
    )


def save_keybind(params: dict) -> dict:
    """Add a new keybind, or update/adopt an existing one.

    No old_keys -> add. old_keys + was_owned -> update in place. old_keys +
    not was_owned -> adopt (copy a locked/distro bind into the user section,
    leaving the original untouched — same semantics as the GTK page).
    """
    new = _entry_from(params)
    if not new.keys.strip() or not new.dispatcher.strip():
        return {"ok": False, "message": "key combo and dispatcher are required"}

    if not params.get("old_keys"):
        ok, message = kbm.add_keybind(new)
    else:
        old = _entry_from(params, prefix="old_")
        if params.get("was_owned", True):
            ok, message = kbm.update_keybind(old, new)
        else:
            ok, message = kbm.adopt_keybind(old, new)

    if ok:
        subprocess.run(["hyprctl", "reload"], check=False)
    return {"ok": ok, "message": message}


def delete_keybind(params: dict) -> dict:
    entry = _entry_from(params)
    ok, message = kbm.remove_keybind(entry)
    if ok:
        subprocess.run(["hyprctl", "reload"], check=False)
    return {"ok": ok, "message": message}


protocol.register("list_keybinds", list_keybinds)
protocol.register("save_keybind", save_keybind)
protocol.register("delete_keybind", delete_keybind)
