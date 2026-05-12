import sys
import os
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from lib import rules_startup_page
from lib.rules_startup_page import AutostartEntry, EnvVar, _serialize_autostart, _serialize_env_vars


def test_serialize_autostart_emits_hl_exec_calls():
    lines = _serialize_autostart([AutostartEntry("waybar", True), AutostartEntry("mako", False)])
    assert lines == ['hl.exec_once("waybar")', 'hl.exec_cmd("mako")']


def test_serialize_env_vars_emits_hl_env_calls():
    lines = _serialize_env_vars([EnvVar("XCURSOR_THEME", "Bibata"), EnvVar("XCURSOR_SIZE", "24")])
    assert lines == ['hl.env("XCURSOR_THEME", "Bibata")', 'hl.env("XCURSOR_SIZE", "24")']


def test_write_conf_writes_user_lua_and_activates_override(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    user = hypr / "user-configs"
    user.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.windowrules")',
            '-- require("user-configs.user_rules_startup") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    monkeypatch.setattr(rules_startup_page, "HYPR_DIR", hypr)
    monkeypatch.setattr(rules_startup_page, "CONF_PATH", user / "user_rules_startup.lua")

    rules_startup_page._write_conf(
        [],
        [],
        [AutostartEntry("waybar", True)],
        [EnvVar("XCURSOR_THEME", "Bibata")],
    )

    content = (user / "user_rules_startup.lua").read_text(encoding="utf-8").splitlines()
    assert 'hl.exec_once("waybar")' in content
    assert 'hl.env("XCURSOR_THEME", "Bibata")' in content
    main_lines = (hypr / "hyprland.lua").read_text(encoding="utf-8").splitlines()
    assert 'require("source.windowrules")' in main_lines
    assert 'require("user-configs.user_rules_startup") -- managed by Cloud Center' in main_lines


def test_upsert_env_vars_preserves_existing_entries_and_updates_cursor_envs(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    user = hypr / "user-configs"
    user.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.windowrules")',
            '-- require("user-configs.user_rules_startup") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    path = user / "user_rules_startup.lua"
    path.write_text(
        '\n'.join([
            '-- Cloud Center user override file for rules and startup hooks.',
            '-- @cloud-center-state = {"autostart":[{"command":"waybar","exec_once":true}],"env_vars":[{"name":"GTK_THEME","value":"Adwaita-dark"},{"name":"XCURSOR_THEME","value":"Afterglow-cursors"}],"layer_rules":[],"window_rules":[]}',
            '',
            'hl.exec_once("waybar")',
            'hl.env("GTK_THEME", "Adwaita-dark")',
            'hl.env("XCURSOR_THEME", "Afterglow-cursors")',
            '',
        ]),
        encoding="utf-8",
    )
    monkeypatch.setattr(rules_startup_page, "HYPR_DIR", hypr)
    monkeypatch.setattr(rules_startup_page, "CONF_PATH", path)

    rules_startup_page.upsert_env_vars({
        "XCURSOR_THEME": "Twilight-cursors",
        "HYPRCURSOR_THEME": "Twilight-cursors",
        "XCURSOR_SIZE": "32",
        "HYPRCURSOR_SIZE": "32",
    })

    content = path.read_text(encoding="utf-8").splitlines()
    assert 'hl.exec_once("waybar")' in content
    assert 'hl.env("GTK_THEME", "Adwaita-dark")' in content
    assert 'hl.env("XCURSOR_THEME", "Twilight-cursors")' in content
    assert 'hl.env("HYPRCURSOR_THEME", "Twilight-cursors")' in content
    assert 'hl.env("XCURSOR_SIZE", "32")' in content
    assert 'hl.env("HYPRCURSOR_SIZE", "32")' in content
    assert 'hl.env("XCURSOR_THEME", "Afterglow-cursors")' not in content
