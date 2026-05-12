import sys
import os
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from lib import monitor_editor
from lib.monitor_editor import _build_monitor_line


def test_build_monitor_line_returns_hl_monitor_call():
    line = _build_monitor_line("DP-1", "2560x1440@155.00Hz", 0, 0, 1.0, 0, True, "")
    assert line == 'hl.monitor({ output = "DP-1", mode = "2560x1440@155.00", position = "0x0", scale = "1" })'


def test_build_monitor_line_disables_output_with_lua_call():
    line = _build_monitor_line("DP-1", "2560x1440@155.00Hz", 0, 0, 1.0, 0, False, "")
    assert line == 'hl.monitor({ output = "DP-1", disable = true })'


def test_write_monitor_line_writes_user_lua_and_activates_override(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    user = hypr / "user-configs"
    user.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.monitors")',
            '-- require("user-configs.user_monitors") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    monkeypatch.setattr(monitor_editor, "HYPR_DIR", hypr)
    monkeypatch.setattr(monitor_editor, "MONITORS_CONF", user / "user_monitors.lua")

    monitor_editor._write_monitor_line(
        "DP-1",
        'hl.monitor({ output = "DP-1", mode = "2560x1440@155.00", position = "0x0", scale = "1" })',
        ["1", "2"],
    )

    content = (user / "user_monitors.lua").read_text(encoding="utf-8").splitlines()
    assert 'hl.monitor({ output = "DP-1", mode = "2560x1440@155.00", position = "0x0", scale = "1" })' in content
    assert 'hl.workspace_rule({ workspace = "1", monitor = "DP-1" })' in content
    assert 'hl.workspace_rule({ workspace = "2", monitor = "DP-1" })' in content
    main_lines = (hypr / "hyprland.lua").read_text(encoding="utf-8").splitlines()
    assert '-- require("source.monitors")' in main_lines
    assert 'require("user-configs.user_monitors") -- managed by Cloud Center' in main_lines
