from pathlib import Path

from lib import hcm_lua, keybind_manager_lua


def _patch_hypr_paths(monkeypatch, hypr: Path, source: Path, user: Path) -> None:
    monkeypatch.setattr(hcm_lua, "HYPR_DIR", hypr)
    monkeypatch.setattr(hcm_lua, "MAIN_LUA", hypr / "hyprland.lua")
    monkeypatch.setattr(hcm_lua, "SOURCE_DIR", source)
    monkeypatch.setattr(hcm_lua, "USER_DIR", user)
    monkeypatch.setattr(hcm_lua, "HYPRLUA_DIR", source)

    monkeypatch.setattr(keybind_manager_lua.hcm_lua, "HYPR_DIR", hypr)
    monkeypatch.setattr(keybind_manager_lua.hcm_lua, "MAIN_LUA", hypr / "hyprland.lua")
    monkeypatch.setattr(keybind_manager_lua.hcm_lua, "SOURCE_DIR", source)
    monkeypatch.setattr(keybind_manager_lua.hcm_lua, "USER_DIR", user)
    monkeypatch.setattr(keybind_manager_lua.hcm_lua, "HYPRLUA_DIR", source)

    monkeypatch.setattr(keybind_manager_lua, "MAIN_LUA", hypr / "hyprland.lua")
    monkeypatch.setattr(keybind_manager_lua, "SOURCE_BINDINGS_LUA", source / "bindings.lua")
    monkeypatch.setattr(keybind_manager_lua, "BINDINGS_LUA", user / "user_bindings.lua")


def test_add_keybind_creates_user_override_and_activates_it(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    source_bindings = source / "bindings.lua"
    source_bindings.write_text(
        'hl.bind("SUPER + Q", hl.dsp.window.close())\n',
        encoding="utf-8",
    )
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.bindings")',
            '-- require("user-configs.user_bindings") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    added = keybind_manager_lua.LuaKeybindEntry(
        keys="SUPER + RETURN",
        dispatcher='hl.dsp.exec_cmd("kitty")',
        opts='',
        raw_line='',
        owned=True,
    )

    success, message = keybind_manager_lua.add_keybind(added)

    assert success is True
    assert message == "keybind added"
    assert source_bindings.read_text(encoding="utf-8") == 'hl.bind("SUPER + Q", hl.dsp.window.close())\n'
    assert (user / "user_bindings.lua").read_text(encoding="utf-8") == '\n'.join([
        'hl.bind("SUPER + Q", hl.dsp.window.close())',
        '',
        '-- --- Cloud Center Additions (managed by Cloud Center) ---',
        'hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))',
        '-- --- End Cloud Center Additions ---',
        '',
    ])
    assert (hypr / "hyprland.lua").read_text(encoding="utf-8") == '\n'.join([
        '-- require("source.bindings")',
        'require("user-configs.user_bindings") -- managed by Cloud Center',
        '',
    ])


def test_scan_keybinds_uses_active_distro_module_without_creating_user_override(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    source_bindings = source / "bindings.lua"
    source_bindings.write_text(
        'hl.bind("SUPER + Q", hl.dsp.window.close())\n',
        encoding="utf-8",
    )
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.bindings")',
            '-- require("user-configs.user_bindings") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    entries = keybind_manager_lua.scan_keybinds()

    assert len(entries) == 1
    assert entries[0].combo == "SUPER + Q"
    assert entries[0].owned is False
    assert not (user / "user_bindings.lua").exists()
    assert (hypr / "hyprland.lua").read_text(encoding="utf-8") == '\n'.join([
        'require("source.bindings")',
        '-- require("user-configs.user_bindings") -- managed by Cloud Center',
        '',
    ])


def test_scan_keybinds_expands_simple_key_variables_from_active_module(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (source / "bindings.lua").write_text(
        '\n'.join([
            'local mainMod = "SUPER"',
            'hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { desc = "Kill active window" })',
            '',
        ]),
        encoding="utf-8",
    )
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.bindings")',
            '-- require("user-configs.user_bindings") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    entries = keybind_manager_lua.scan_keybinds()

    assert len(entries) == 1
    assert entries[0].combo == "SUPER + Q"
    assert entries[0].dispatcher == "hl.dsp.window.close()"
    assert entries[0].owned is False


def test_parse_bind_line_ignores_trailing_lua_comment():
    """Regression: a bind line with a trailing -- comment must still parse correctly."""
    line = 'hl.bind("SUPER + Q", hl.dsp.window.close()) -- close active window'
    entry = keybind_manager_lua._parse_bind_line(line)
    assert entry is not None, "line with trailing comment must not be dropped"
    assert entry.combo == "SUPER + Q"
    assert entry.dispatcher == "hl.dsp.window.close()"


def test_parse_bind_line_comment_containing_paren_does_not_corrupt_dispatcher():
    """Regression: a trailing Lua comment with ')' inside must not corrupt the dispatcher.

    rfind(')') finds the ')' inside the comment instead of the actual closing paren of
    hl.bind(…), so either the line is dropped (None) or the dispatcher includes
    comment text.  Currently FAILS.  Fix: strip the '--' comment before paren matching.
    """
    line = 'hl.bind("SUPER + Q", hl.dsp.window.close()) -- close (active) window'
    entry = keybind_manager_lua._parse_bind_line(line)
    assert entry is not None, "line with paren-containing comment must not be dropped"
    assert entry.combo == "SUPER + Q"
    assert entry.dispatcher == "hl.dsp.window.close()", (
        f"dispatcher was corrupted to: {entry.dispatcher!r}"
    )


def test_add_keybind_returns_error_tuple_when_hyprland_lua_missing(tmp_path, monkeypatch):
    """Regression: add_keybind must return (False, msg) when hyprland.lua is absent.

    Previously _ensure_user_bindings_lua raised FileNotFoundError, which escaped
    the _do_add daemon thread and failed silently in the UI.
    """
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    # source bindings exist but hyprland.lua is intentionally absent
    (source / "bindings.lua").write_text(
        'hl.bind("SUPER + Q", hl.dsp.window.close())\n',
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    entry = keybind_manager_lua.LuaKeybindEntry(
        keys="SUPER + RETURN",
        dispatcher='hl.dsp.exec_cmd("kitty")',
        opts="",
        raw_line="",
        owned=True,
    )

    # Must not raise; must return an error tuple instead
    ok, msg = keybind_manager_lua.add_keybind(entry)
    assert ok is False
    assert msg  # non-empty error message


def test_cloud_center_routes_hkbm_to_lua_keybind_manager():
    cloud_center = Path(__file__).resolve().parents[1] / "cloud-center.py"
    source = cloud_center.read_text(encoding="utf-8")

    assert "import lib.keybind_manager_lua as keybind_manager" in source
    assert '"__hkbm__":  lambda: keybind_manager.LuaKeybindManagerPage(self._toast_ov),' in source
