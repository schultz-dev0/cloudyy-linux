from pathlib import Path

import pytest

from lib import hcm_lua


def _patch_hypr_paths(monkeypatch, hypr: Path, source: Path, user: Path) -> None:
    monkeypatch.setattr(hcm_lua, "HYPR_DIR", hypr)
    monkeypatch.setattr(hcm_lua, "MAIN_LUA", hypr / "hyprland.lua")
    monkeypatch.setattr(hcm_lua, "SOURCE_DIR", source)
    monkeypatch.setattr(hcm_lua, "USER_DIR", user)


def _write_source_module(source: Path, name: str = "bindings.lua") -> Path:
    module = source / name
    module.write_text("-- @description = bindings\n", encoding="utf-8")
    return module


def test_scan_lua_files_marks_user_override_when_hyprland_lua_activates_it(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    _write_source_module(source)
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text(
        '-- require("source.bindings")\n'
        'require("user-configs.user_bindings") -- managed by Cloud Center\n',
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    files = hcm_lua.scan_lua_files()
    status_by_name = {f.filename: f.status.name for f in files}
    assert status_by_name["bindings.lua"] == "USER_OVERRIDE"


@pytest.mark.parametrize("spacing", ["  ", "\t"])
def test_scan_lua_files_treats_managed_require_spacing_as_active_override(tmp_path, monkeypatch, spacing):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    _write_source_module(source)
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text(
        f'require("user-configs.user_bindings"){spacing}-- managed by Cloud Center\n',
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    files = hcm_lua.scan_lua_files()
    status_by_name = {f.filename: f.status.name for f in files}
    assert status_by_name["bindings.lua"] == "USER_OVERRIDE"


def test_scan_lua_files_keeps_distro_active_when_user_override_exists_but_is_not_required(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    _write_source_module(source)
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text('require("source.bindings")\n', encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    files = hcm_lua.scan_lua_files()

    assert files[0].status is hcm_lua.LuaFileStatus.DISTRO


def test_scan_lua_files_marks_distro_when_user_override_is_missing(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    _write_source_module(source)
    (hypr / "hyprland.lua").write_text('require("source.bindings")\n', encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    files = hcm_lua.scan_lua_files()

    assert files[0].status is hcm_lua.LuaFileStatus.DISTRO


def test_scan_lua_files_marks_distro_when_hyprland_lua_is_missing(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    _write_source_module(source)
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    files = hcm_lua.scan_lua_files()

    assert files[0].status is hcm_lua.LuaFileStatus.DISTRO


def test_preview_path_uses_active_distro_file_when_user_override_exists_but_is_inactive(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    distro_module = _write_source_module(source)
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text('require("source.bindings")\n', encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    config = hcm_lua.scan_lua_files()[0]

    assert hcm_lua._preview_path_for(config) == distro_module


def test_scan_lua_files_returns_empty_when_source_directory_is_missing(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    user.mkdir(parents=True)
    _patch_hypr_paths(monkeypatch, hypr, source, user)

    assert hcm_lua.scan_lua_files() == []


def test_switch_to_user_override_creates_user_copy_and_activates_user_require(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    module = _write_source_module(source)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.bindings")',
            '-- require("user-configs.user_bindings") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)
    config = hcm_lua.LuaConfigFile(
        filename="bindings.lua",
        path=module,
        description="bindings",
        status=hcm_lua.LuaFileStatus.DISTRO,
    )

    result = hcm_lua.switch_to_user_override(config)
    edit_path = result.edit_path

    assert edit_path == user / "user_bindings.lua"
    assert edit_path.read_text(encoding="utf-8") == module.read_text(encoding="utf-8")
    assert result.activated is True
    assert result.message == "Saved user_bindings.lua — user override activated"
    assert (hypr / "hyprland.lua").read_text(encoding="utf-8") == '\n'.join([
        '-- require("source.bindings")',
        'require("user-configs.user_bindings") -- managed by Cloud Center',
        '',
    ])


def test_switch_to_user_override_reports_activation_failure_when_hyprland_lua_is_missing(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    module = _write_source_module(source)
    _patch_hypr_paths(monkeypatch, hypr, source, user)
    config = hcm_lua.LuaConfigFile(
        filename="bindings.lua",
        path=module,
        description="bindings",
        status=hcm_lua.LuaFileStatus.DISTRO,
    )

    result = hcm_lua.switch_to_user_override(config)

    assert result.edit_path == user / "user_bindings.lua"
    assert result.edit_path.read_text(encoding="utf-8") == module.read_text(encoding="utf-8")
    assert result.activated is False
    assert result.message == "Created user_bindings.lua, but could not activate it because hyprland.lua is missing"


def test_revert_to_baseline_deletes_user_override_and_restores_source_require(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    module = _write_source_module(source)
    user_module = user / "user_bindings.lua"
    user_module.write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            '-- require("source.bindings")',
            'require("user-configs.user_bindings") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    _patch_hypr_paths(monkeypatch, hypr, source, user)
    config = hcm_lua.LuaConfigFile(
        filename="bindings.lua",
        path=module,
        description="bindings",
        status=hcm_lua.LuaFileStatus.USER_OVERRIDE,
    )

    ok, message = hcm_lua.revert_to_baseline(config)

    assert ok is True
    assert message == "Reverted bindings.lua to distro source"
    assert not user_module.exists()
    assert (hypr / "hyprland.lua").read_text(encoding="utf-8") == '\n'.join([
        'require("source.bindings")',
        '-- require("user-configs.user_bindings") -- managed by Cloud Center',
        '',
    ])


def test_revert_to_baseline_reports_loader_failure_when_hyprland_lua_is_missing(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    module = _write_source_module(source)
    user_module = user / "user_bindings.lua"
    user_module.write_text("-- @description = user bindings\n", encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)
    config = hcm_lua.LuaConfigFile(
        filename="bindings.lua",
        path=module,
        description="bindings",
        status=hcm_lua.LuaFileStatus.USER_OVERRIDE,
    )

    ok, message = hcm_lua.revert_to_baseline(config)

    assert ok is False
    assert message == "Deleted user_bindings.lua, but could not activate distro source because hyprland.lua is missing"
    assert not user_module.exists()


def test_revert_to_baseline_reports_when_no_user_override_exists(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    module = _write_source_module(source)
    (hypr / "hyprland.lua").write_text('require("source.bindings")\n', encoding="utf-8")
    _patch_hypr_paths(monkeypatch, hypr, source, user)
    config = hcm_lua.LuaConfigFile(
        filename="bindings.lua",
        path=module,
        description="bindings",
        status=hcm_lua.LuaFileStatus.DISTRO,
    )

    ok, message = hcm_lua.revert_to_baseline(config)

    assert ok is False
    assert message == "No user override found — already using distro source"


def test_cloud_center_wires_hcm_page_id():
    cloud_center = (
        Path(__file__).resolve().parents[1]
        / "cloud-center.py"
    ).read_text(encoding="utf-8")

    assert '"config-manager": "__hcm__"' in cloud_center
    assert '"__hcm__": {"id": "__hcm__", "title": "Lua Config Manager"' in cloud_center
    assert '("Advanced",        ["__hcm__"])' in cloud_center
    assert '"__hcm__"' in cloud_center
    assert 'lambda: hcm.LuaConfigManagerPage(self._toast_ov)' in cloud_center
