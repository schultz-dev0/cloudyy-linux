import os
import subprocess
from pathlib import Path

from lib import hypr_persist_lua


SCRIPT = Path(__file__).resolve().parents[1] / "hypr_persist.sh"


def _run(hypr: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(hypr.parent.parent)
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(hypr)],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def _lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def test_hypr_persist_input_change_only_materializes_input_surface(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.lookandfeel")',
            '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center',
            'require("source.animations")',
            '-- require("user-configs.user_animations") -- managed by Cloud Center',
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '-- require("user-configs.user_cursor") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "lookandfeel.lua").write_text(
        "hl.config({ general = { gaps_in = 2 } })\n",
        encoding="utf-8",
    )
    (source / "animations.lua").write_text("hl.config({ animations = { enabled = true } })\n", encoding="utf-8")
    (source / "input.lua").write_text("hl.config({ input = { kb_layout = 'us' } })\n", encoding="utf-8")
    (hypr / ".cloud-center-state.json").write_text(
        (
            "{\n"
            '  "animations:enabled": "true",\n'
            '  "animations:bezier": "myBezier6,0.833,-1.102,1.0,-1.175",\n'
            '  "animations:animation": "windows,1,4,myBezier6"\n'
            "}\n"
        ),
        encoding="utf-8",
    )

    result = _run(hypr, "input:kb_layout", "de")

    assert result.returncode == 0, result.stderr or result.stdout
    assert (user / "user_input.lua").exists()
    assert not (user / "user_lookandfeel.lua").exists()
    assert not (user / "user_animations.lua").exists()
    assert not (user / "user_cursor.lua").exists()
    assert not (user / "user_lookandfeel.conf").exists()
    assert 'kb_layout = "de"' in (user / "user_input.lua").read_text(encoding="utf-8")
    main_lines = _lines(hypr / "hyprland.lua")
    assert 'require("source.lookandfeel")' in main_lines
    assert '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center' in main_lines
    assert 'require("source.animations")' in main_lines
    assert '-- require("user-configs.user_animations") -- managed by Cloud Center' in main_lines
    assert '-- require("source.input")' in main_lines
    assert 'require("user-configs.user_input") -- managed by Cloud Center' in main_lines


def test_hypr_persist_reset_page_restores_source_activation(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "input.lua").write_text(
        'hl.config({ input = { kb_layout = "us", touchpad = { natural_scroll = false } } })\n',
        encoding="utf-8",
    )

    set_result = _run(hypr, "input:kb_layout", "de")
    assert set_result.returncode == 0, set_result.stderr or set_result.stdout
    assert 'require("user-configs.user_input") -- managed by Cloud Center' in _lines(hypr / "hyprland.lua")

    reset_result = _run(hypr, "reset-page", "input")

    assert reset_result.returncode == 0, reset_result.stderr or reset_result.stdout
    main_lines = _lines(hypr / "hyprland.lua")
    assert 'require("source.input")' in main_lines
    assert '-- require("user-configs.user_input") -- managed by Cloud Center' in main_lines


def test_hypr_persist_quotes_hyphenated_nested_keys_in_lua_output(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "input.lua").write_text(
        'hl.config({ input = { touchpad = { ["tap-to-click"] = false } } })\n',
        encoding="utf-8",
    )

    result = _run(hypr, "input:touchpad:tap-to-click", "true")

    assert result.returncode == 0, result.stderr or result.stdout
    content = (user / "user_input.lua").read_text(encoding="utf-8")
    assert '["tap-to-click"] = true' in content


def test_hypr_persist_does_not_resurrect_legacy_conf_state_once_json_exists(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.lookandfeel")',
            '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center',
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "lookandfeel.lua").write_text(
        "hl.config({ general = { gaps_in = 2 } })\n",
        encoding="utf-8",
    )
    (source / "input.lua").write_text(
        'hl.config({ input = { kb_layout = "us" } })\n',
        encoding="utf-8",
    )
    (user / "user_input.conf").write_text(
        '\n'.join([
            "input {",
            "    kb_layout = fr",
            "}",
            "",
        ]),
        encoding="utf-8",
    )
    (hypr / ".cloud-center-state.json").write_text("{}\n", encoding="utf-8")

    result = _run(hypr, "general:gaps_in", "8")

    assert result.returncode == 0, result.stderr or result.stdout
    assert not (user / "user_input.lua").exists()
    main_lines = _lines(hypr / "hyprland.lua")
    assert 'require("source.input")' in main_lines
    assert '-- require("user-configs.user_input") -- managed by Cloud Center' in main_lines


def test_hypr_persist_does_not_resurrect_legacy_conf_state_once_managed_lua_exists(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)

    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.lookandfeel")',
            '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center',
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "lookandfeel.lua").write_text(
        "hl.config({ general = { gaps_in = 2 } })\n",
        encoding="utf-8",
    )
    (source / "input.lua").write_text(
        'hl.config({ input = { kb_layout = "us" } })\n',
        encoding="utf-8",
    )
    (user / "user_input.conf").write_text(
        '\n'.join([
            "input {",
            "    kb_layout = fr",
            "}",
            "",
        ]),
        encoding="utf-8",
    )
    (user / "user_input.lua").write_text(
        '\n'.join([
            "-- Cloud Center user override file for input configuration.",
            "-- @cloud-center-state = {}",
            "",
        ]),
        encoding="utf-8",
    )

    result = _run(hypr, "general:gaps_in", "8")

    assert result.returncode == 0, result.stderr or result.stdout
    assert 'kb_layout = "fr"' not in (user / "user_input.lua").read_text(encoding="utf-8")
    main_lines = _lines(hypr / "hyprland.lua")
    assert 'require("source.input")' in main_lines
    assert '-- require("user-configs.user_input") -- managed by Cloud Center' in main_lines


def _make_minimal_hypr(hypr: Path) -> None:
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.lookandfeel")',
            '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center',
            'require("source.animations")',
            '-- require("user-configs.user_animations") -- managed by Cloud Center',
            'require("source.input")',
            '-- require("user-configs.user_input") -- managed by Cloud Center',
            '-- require("user-configs.user_cursor") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )
    (source / "lookandfeel.lua").write_text("hl.config({ general = { gaps_in = 2 } })\n", encoding="utf-8")
    (source / "animations.lua").write_text("hl.config({ animations = { enabled = true } })\n", encoding="utf-8")
    (source / "input.lua").write_text("hl.config({ input = { kb_layout = 'us' } })\n", encoding="utf-8")


def test_main_archives_legacy_conf_tree_on_first_persist(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    _make_minimal_hypr(hypr)
    (hypr / "hyprland.conf").write_text("# legacy main conf\n", encoding="utf-8")
    (hypr / "hypridle.conf").write_text("# hypridle\n", encoding="utf-8")
    (hypr / "hyprlock.conf").write_text("# hyprlock\n", encoding="utf-8")
    (hypr / "xdph.conf").write_text("# xdph\n", encoding="utf-8")

    rc = hypr_persist_lua.main(["hypr_persist_lua", "general:gaps_in", "8", str(hypr)])

    assert rc == 0
    assert not (hypr / "hyprland.conf").exists(), "legacy conf must be archived"
    assert (hypr / ".legacy" / "hyprland.conf").exists(), "legacy conf must be in .legacy/"
    for sidecar in ("hypridle.conf", "hyprlock.conf", "xdph.conf"):
        assert (hypr / sidecar).exists(), f"{sidecar} must not be archived"
        assert not (hypr / ".legacy" / sidecar).exists(), f"{sidecar} must not appear in .legacy/"


def test_main_does_not_re_archive_on_second_persist(tmp_path):
    hypr = tmp_path / ".config" / "hypr"
    _make_minimal_hypr(hypr)
    (hypr / "hyprland.conf").write_text("# legacy main conf\n", encoding="utf-8")

    hypr_persist_lua.main(["hypr_persist_lua", "general:gaps_in", "8", str(hypr)])
    # Simulate a new conf file appearing after cutover (should not be re-archived in a new run
    # because the sentinel is present).
    stray = hypr / "stray.conf"
    stray.write_text("# stray\n", encoding="utf-8")

    hypr_persist_lua.main(["hypr_persist_lua", "general:gaps_in", "10", str(hypr)])

    assert stray.exists(), "stray conf written after cutover must not be archived on second run"


def test_managed_lua_state_wins_over_conflicting_json(tmp_path):
    """Regression: managed Lua sidecar state must take priority over .cloud-center-state.json."""
    hypr = tmp_path / ".config" / "hypr"
    user = hypr / "user-configs"
    user.mkdir(parents=True)

    # Lua sidecar says gaps_in = 5
    lua_state = {"general:gaps_in": "5"}
    (user / "user_lookandfeel.lua").write_text(
        "\n".join([
            "-- Cloud Center user override file for lookandfeel configuration.",
            f"-- @cloud-center-state = {__import__('json').dumps(lua_state)}",
            "",
        ]),
        encoding="utf-8",
    )

    # JSON says gaps_in = 99 — stale override that must lose
    (hypr / ".cloud-center-state.json").write_text(
        __import__('json').dumps({"general:gaps_in": "99"}),
        encoding="utf-8",
    )

    state = hypr_persist_lua.load_state(hypr)

    assert state.get("general:gaps_in") == "5", (
        f"Expected managed Lua state '5' to win over JSON '99', got {state.get('general:gaps_in')!r}"
    )


def test_update_activation_rewrites_hyprland_lua_atomically(tmp_path, monkeypatch):
    hypr = tmp_path / ".config" / "hypr"
    hypr.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text(
        '\n'.join([
            'require("source.lookandfeel")',
            '-- require("user-configs.user_lookandfeel") -- managed by Cloud Center',
            '',
        ]),
        encoding="utf-8",
    )

    calls: list[tuple[str, str]] = []
    real_replace = hypr_persist_lua.os.replace

    def track_replace(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
        calls.append((os.fspath(src), os.fspath(dst)))
        real_replace(src, dst)

    monkeypatch.setattr(hypr_persist_lua.os, "replace", track_replace)

    hypr_persist_lua.update_activation(hypr, {"general:gaps_in": "8"})

    assert calls
    assert calls[-1][1] == os.fspath(hypr / "hyprland.lua")
