# Total Lua Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Hyprland and Cloud Center's Hyprland-facing config management to a Lua-only runtime while preserving the existing `source/` vs `user-configs/` override model and archiving legacy `.conf` files under `.config/hypr/.legacy/`.

**Architecture:** Keep `~/.config/hypr/hyprland.lua` as a thin switchboard that activates categorized Lua modules from `source/` and `user-configs/`. Replace `.conf`-specific Cloud Center managers with Lua-aware managers that toggle exact `require(...)` lines in `hyprland.lua`, write override modules into `user-configs/`, and never rewrite distro defaults in `source/`.

**Tech Stack:** Python 3, GTK4/Libadwaita, pytest, Lua module files under `.config/hypr/`, existing `hypr_persist.sh` shell entrypoint with embedded Python

---

## File Structure

### Active runtime files

- Modify: `.config/hypr/hyprland.lua`
- Create: `.config/hypr/source/lookandfeel.lua`
- Create: `.config/hypr/source/colors.lua`
- Create: `.config/hypr/source/animations.lua`
- Create: `.config/hypr/source/input.lua`
- Create: `.config/hypr/source/bindings.lua`
- Create: `.config/hypr/source/monitors.lua`
- Create: `.config/hypr/source/windowrules.lua`
- Create: `.config/hypr/source/autostart.lua`
- Create: `.config/hypr/source/variables.lua`
- Create: `.config/hypr/user-configs/user_lookandfeel.lua`
- Create: `.config/hypr/user-configs/user_animations.lua`
- Create: `.config/hypr/user-configs/user_input.lua`
- Create: `.config/hypr/user-configs/user_cursor.lua`
- Create: `.config/hypr/user-configs/user_bindings.lua`
- Create: `.config/hypr/user-configs/user_monitors.lua`
- Create: `.config/hypr/user-configs/user_rules_startup.lua`
- Create: `.config/hypr/user-configs/user_variables.lua`
- Create: `.config/hypr/.legacy/` (directory for archived `.conf` files after cutover)

### Cloud Center runtime helpers

- Create: `cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/cursor_page.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/bezier_editor.py`
- Modify: `cloudyy_scripts/cloud-center-v2/cloud-center.py`
- Modify: `cloudyy_scripts/cloud-center-v2/hypr_persist.sh`
- Modify: `cloudyy_scripts/cloud-center-v2/config.yaml`

### Tests

- Create: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py`

### Docs

- Modify: `cloudyy_scripts/cloud-center-v2/docs/overview-keybinds.md` (only if keybind semantics or names change during migration)
- Create: `cloudyy_scripts/cloud-center-v2/docs/superpowers/plans/2026-05-12-total-lua-migration.md`

---

### Task 1: Add shared Lua runtime helpers

**Files:**
- Create: `cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path

from lib.hyprlua_runtime import (
    ensure_user_override_active,
    ensure_source_active,
    module_paths,
)


def test_module_paths_for_bindings():
    paths = module_paths("bindings")
    assert paths.source_module == 'require("source.bindings")'
    assert paths.user_module == 'require("user-configs.user_bindings") -- managed by Cloud Center'


def test_activate_user_override_comments_source_line():
    original = '\n'.join([
        'require("source.bindings")',
        'require("source.input")',
        '',
    ])
    updated = ensure_user_override_active(original, "bindings")
    assert '-- require("source.bindings")' in updated
    assert 'require("user-configs.user_bindings") -- managed by Cloud Center' in updated
    assert updated.count('user-configs.user_bindings') == 1


def test_revert_to_source_removes_managed_user_line():
    original = '\n'.join([
        '-- require("source.bindings")',
        'require("user-configs.user_bindings") -- managed by Cloud Center',
        '',
    ])
    updated = ensure_source_active(original, "bindings")
    assert 'require("source.bindings")' in updated
    assert 'user-configs.user_bindings' not in updated
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'lib.hyprlua_runtime'`

- [ ] **Step 3: Write minimal implementation**

```python
from dataclasses import dataclass


@dataclass(frozen=True)
class ModulePaths:
    surface: str
    source_module: str
    source_comment: str
    user_module: str


def module_paths(surface: str) -> ModulePaths:
    return ModulePaths(
        surface=surface,
        source_module=f'require("source.{surface}")',
        source_comment=f'-- require("source.{surface}")',
        user_module=f'require("user-configs.user_{surface}") -- managed by Cloud Center',
    )


def ensure_user_override_active(text: str, surface: str) -> str:
    paths = module_paths(surface)
    updated = text.replace(paths.source_module, paths.source_comment)
    if paths.user_module not in updated:
        updated = updated.rstrip() + "\n" + paths.user_module + "\n"
    return updated


def ensure_source_active(text: str, surface: str) -> str:
    paths = module_paths(surface)
    updated = text.replace(paths.source_comment, paths.source_module)
    updated = "\n".join(
        line for line in updated.splitlines()
        if line.strip() != paths.user_module
    )
    return updated + ("\n" if updated else "")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q`
Expected: PASS with `3 passed`

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py
git commit -m "feat: add shared hypr lua runtime helpers"
```

### Task 2: Convert the active Hypr config tree to `source/*.lua` and `user-configs/*.lua`

**Files:**
- Modify: `.config/hypr/hyprland.lua`
- Create: `.config/hypr/source/lookandfeel.lua`
- Create: `.config/hypr/source/colors.lua`
- Create: `.config/hypr/source/animations.lua`
- Create: `.config/hypr/source/input.lua`
- Create: `.config/hypr/source/bindings.lua`
- Create: `.config/hypr/source/monitors.lua`
- Create: `.config/hypr/source/windowrules.lua`
- Create: `.config/hypr/source/autostart.lua`
- Create: `.config/hypr/source/variables.lua`
- Create: `.config/hypr/user-configs/user_lookandfeel.lua`
- Create: `.config/hypr/user-configs/user_animations.lua`
- Create: `.config/hypr/user-configs/user_input.lua`
- Create: `.config/hypr/user-configs/user_bindings.lua`
- Create: `.config/hypr/user-configs/user_monitors.lua`
- Create: `.config/hypr/user-configs/user_rules_startup.lua`
- Create: `.config/hypr/user-configs/user_variables.lua`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path


def test_hyprland_lua_points_at_source_and_user_modules():
    repo_root = Path(__file__).resolve().parents[3]
    text = (repo_root / ".config/hypr/hyprland.lua").read_text(encoding="utf-8")
    assert 'require("source.lookandfeel")' in text
    assert 'require("source.bindings")' in text
    assert 'require("source.colors")' in text
    assert 'require("user-configs.user_lookandfeel")' not in text
    assert 'require("user-configs.user_bindings")' not in text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q -k source_and_user_modules`
Expected: FAIL because `hyprland.lua` still only requires flat `.hyprlua` modules

- [ ] **Step 3: Write minimal implementation**

```lua
-- .config/hypr/hyprland.lua
local home = os.getenv("HOME")
package.path = package.path
    .. ";" .. home .. "/.config/hypr/source/?.lua"
    .. ";" .. home .. "/.config/hypr/user-configs/?.lua"

require("source.colors")
require("source.variables")
require("source.monitors")
require("source.lookandfeel")
require("source.animations")
require("source.input")
require("source.autostart")
require("source.windowrules")
require("source.bindings")
```

```lua
-- .config/hypr/source/colors.lua
return dofile(os.getenv("HOME") .. "/.config/hypr/.hyprlua/colors.lua")
```

```lua
-- .config/hypr/source/bindings.lua
local mainMod = "SUPER"
hl.bind(mainMod .. " + W", hl.dsp.window.close(), { desc = "Kill active window" })
```

```lua
-- .config/hypr/user-configs/user_bindings.lua
-- Cloud Center user override file.
-- This file is inactive until Cloud Center switches hyprland.lua to use it.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q -k source_and_user_modules`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .config/hypr/hyprland.lua .config/hypr/source .config/hypr/user-configs
git commit -m "feat: convert hypr config tree to source and user lua modules"
```

### Task 3: Replace the config manager with a Lua-aware `source/` vs `user-configs/` manager

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/cloud-center.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path

from lib import hcm_lua


def test_scan_lua_files_marks_user_override_when_hyprland_lua_activates_it(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    (source / "bindings.lua").write_text("-- @description = bindings\n", encoding="utf-8")
    (user / "user_bindings.lua").write_text("-- @description = user bindings\n", encoding="utf-8")
    (hypr / "hyprland.lua").write_text(
        '-- require("source.bindings")\n'
        'require("user-configs.user_bindings") -- managed by Cloud Center\n',
        encoding="utf-8",
    )
    monkeypatch.setattr(hcm_lua, "HYPR_DIR", hypr)
    monkeypatch.setattr(hcm_lua, "MAIN_LUA", hypr / "hyprland.lua")
    monkeypatch.setattr(hcm_lua, "SOURCE_DIR", source)
    monkeypatch.setattr(hcm_lua, "USER_DIR", user)

    files = hcm_lua.scan_lua_files()
    status_by_name = {f.filename: f.status.name for f in files}
    assert status_by_name["bindings.lua"] == "USER_OVERRIDE"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py -q`
Expected: FAIL because `hcm_lua.py` still scans `.hyprlua/` and has no distro/user override status

- [ ] **Step 3: Write minimal implementation**

```python
SOURCE_DIR = HYPR_DIR / "source"
USER_DIR = HYPR_DIR / "user-configs"


class LuaFileStatus(Enum):
    DISTRO = auto()
    USER_OVERRIDE = auto()


def _active_require_lines() -> set[str]:
    if not MAIN_LUA.exists():
        return set()
    return {
        line.strip()
        for line in MAIN_LUA.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith('require("')
    }


def scan_lua_files() -> list[LuaConfigFile]:
    active = _active_require_lines()
    files: list[LuaConfigFile] = []
    for path in sorted(SOURCE_DIR.glob("*.lua")):
        user_path = USER_DIR / f"user_{path.name}"
        status = LuaFileStatus.USER_OVERRIDE if (
            user_path.exists()
            and f'require("user-configs.user_{path.stem}") -- managed by Cloud Center' in active
        ) else LuaFileStatus.DISTRO
        files.append(LuaConfigFile(path.name, path, _read_lua_description(path), status))
    return files
```

```python
# cloud-center.py import block
import lib.hcm_lua as hcm
import lib.keybind_manager_lua as keybind_manager
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py \
        cloudyy_scripts/cloud-center-v2/cloud-center.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py
git commit -m "feat: switch config manager to source and user lua modules"
```

### Task 4: Replace the keybind manager with the Lua activation model

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/cloud-center.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path

from lib import keybind_manager_lua


def test_ensure_bindings_lua_comments_source_and_enables_user_override(tmp_path, monkeypatch):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    (source / "bindings.lua").write_text('hl.bind("SUPER + W", hl.dsp.window.close())\n', encoding="utf-8")
    (hypr / "hyprland.lua").write_text('require("source.bindings")\n', encoding="utf-8")
    monkeypatch.setattr(keybind_manager_lua, "HYPR_DIR", hypr)
    monkeypatch.setattr(keybind_manager_lua, "BINDINGS_LUA", user / "user_bindings.lua")
    monkeypatch.setattr(keybind_manager_lua, "MAIN_LUA", hypr / "hyprland.lua")

    keybind_manager_lua._ensure_bindings_lua()

    text = (hypr / "hyprland.lua").read_text(encoding="utf-8")
    assert '-- require("source.bindings")' in text
    assert 'require("user-configs.user_bindings") -- managed by Cloud Center' in text
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py -q`
Expected: FAIL because the manager still targets `.hyprlua/bindings.lua`

- [ ] **Step 3: Write minimal implementation**

```python
BINDINGS_LUA = hcm_lua.USER_DIR / "user_bindings.lua"
SOURCE_BINDINGS_LUA = hcm_lua.SOURCE_DIR / "bindings.lua"


def _ensure_bindings_lua() -> None:
    if not BINDINGS_LUA.exists() and SOURCE_BINDINGS_LUA.exists():
        BINDINGS_LUA.write_text(
            SOURCE_BINDINGS_LUA.read_text(encoding="utf-8")
            + f"\n{_CC_BEGIN}\n{_CC_END}\n",
            encoding="utf-8",
        )
    elif not BINDINGS_LUA.exists():
        BINDINGS_LUA.write_text(f"{_CC_BEGIN}\n{_CC_END}\n", encoding="utf-8")

    content = MAIN_LUA.read_text(encoding="utf-8")
    content = ensure_user_override_active(content, "bindings")
    MAIN_LUA.write_text(content, encoding="utf-8")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py \
        cloudyy_scripts/cloud-center-v2/cloud-center.py \
        cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py
git commit -m "feat: migrate keybind manager to lua override activation"
```

### Task 5: Retool `hypr_persist.sh`, `config.yaml`, and cursor/bezier callers for Lua overrides

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/hypr_persist.sh`
- Modify: `cloudyy_scripts/cloud-center-v2/config.yaml`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/cursor_page.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/bezier_editor.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path
import subprocess


def test_hypr_persist_writes_user_lua_and_comments_source_line(tmp_path):
    hypr = tmp_path / "hypr"
    source = hypr / "source"
    user = hypr / "user-configs"
    source.mkdir(parents=True)
    user.mkdir(parents=True)
    (hypr / "hyprland.lua").write_text('require("source.lookandfeel")\n', encoding="utf-8")
    (source / "lookandfeel.lua").write_text("hl.config({ general = { gaps_in = 2 } })\n", encoding="utf-8")

    subprocess.run(
        [
            "bash",
            "cloudyy_scripts/cloud-center-v2/hypr_persist.sh",
            "general:gaps_in",
            "8",
            str(hypr),
        ],
        check=False,
    )

    assert (user / "user_lookandfeel.lua").exists()
    main = (hypr / "hyprland.lua").read_text(encoding="utf-8")
    assert '-- require("source.lookandfeel")' in main
    assert 'require("user-configs.user_lookandfeel") -- managed by Cloud Center' in main
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py -q`
Expected: FAIL because `hypr_persist.sh` still writes `.conf` files and edits `hyprland.conf`

- [ ] **Step 3: Write minimal implementation**

```python
TITLE_BY_SECTION = {
    "general": "-- Cloud Center — user-configs/user_lookandfeel.lua",
    "decoration": "-- Cloud Center — user-configs/user_lookandfeel.lua",
    "animations": "-- Cloud Center — user-configs/user_animations.lua",
    "input": "-- Cloud Center — user-configs/user_input.lua",
    "cursor": "-- Cloud Center — user-configs/user_cursor.lua",
}


def build_lua_lines(title: str, sections: list[str]) -> list[str]:
    lines = [title, "-- Managed automatically by hypr_persist.sh.", ""]
    for section in sections:
        if section == "animations":
            lines.append("hl.config({ animations = { enabled = true } })")
        elif section == "input":
            lines.append('hl.config({ input = { follow_mouse = 1 } })')
    return lines
```

```yaml
# config.yaml action example
command: |
  hyprctl keyword general:gaps_in {value} &&
  ~/cloudyy_scripts/cloud-center-v2/hypr_persist.sh general:gaps_in {value}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/hypr_persist.sh \
        cloudyy_scripts/cloud-center-v2/config.yaml \
        cloudyy_scripts/cloud-center-v2/lib/cursor_page.py \
        cloudyy_scripts/cloud-center-v2/lib/bezier_editor.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py
git commit -m "feat: switch hypr persist flow to lua override files"
```

### Task 6: Move monitor editor and rules/startup page to Lua files

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py`
- Modify: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py`
- Create: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py`

- [ ] **Step 1: Write the failing tests**

```python
from lib.monitor_editor import _build_monitor_line


def test_build_monitor_line_returns_hl_monitor_call():
    line = _build_monitor_line("DP-1", "2560x1440@155.00Hz", 0, 0, 1.0, 0, True, "")
    assert line == 'hl.monitor({ output = "DP-1", mode = "2560x1440@155.00", position = "0x0", scale = "1" })'
```

```python
from lib.rules_startup_page import _serialize_autostart, AutostartEntry


def test_serialize_autostart_emits_hl_exec_calls():
    lines = _serialize_autostart([AutostartEntry("waybar", True)])
    assert lines == ['hl.exec_once("waybar")']
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q`
Expected: FAIL because both modules still emit `.conf` syntax

- [ ] **Step 3: Write minimal implementation**

```python
def _build_monitor_line(name, mode, pos_x, pos_y, scale, transform, enabled, mirror_of):
    if not enabled:
        return f'hl.monitor({{ output = "{name}", disable = true }})'
    mode_conf = re.sub(r"Hz$", "", mode, flags=re.IGNORECASE)
    return (
        f'hl.monitor({{ output = "{name}", mode = "{mode_conf}", '
        f'position = "{pos_x}x{pos_y}", scale = "{scale:.4g}" }})'
    )
```

```python
def _serialize_autostart(entries: list[AutostartEntry]) -> list[str]:
    return [
        f'hl.exec_once("{e.command}")' if e.exec_once else f'hl.exec_cmd("{e.command}")'
        for e in entries
    ]


def _serialize_env_vars(vars_: list[EnvVar]) -> list[str]:
    return [f'hl.env("{v.name}", "{v.value}")' for v in vars_]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py \
        cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py \
        cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py
git commit -m "feat: port monitor and rules startup pages to lua"
```

### Task 7: Add one-time migration/archive flow and final verification

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py`
- Modify: `cloudyy_scripts/cloud-center-v2/cloud-center.py`
- Create: `.config/hypr/.legacy/`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`

- [ ] **Step 1: Write the failing test**

```python
from pathlib import Path

from lib.hyprlua_runtime import archive_legacy_conf_tree


def test_archive_legacy_conf_tree_moves_conf_files(tmp_path):
    hypr = tmp_path / "hypr"
    hypr.mkdir()
    legacy_conf = hypr / "hyprland.conf"
    legacy_conf.write_text("source = ~/.config/hypr/source/lookandfeel.conf\n", encoding="utf-8")

    archive_legacy_conf_tree(hypr)

    assert not legacy_conf.exists()
    assert (hypr / ".legacy" / "hyprland.conf").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q -k archive_legacy_conf_tree`
Expected: FAIL because no archive helper exists

- [ ] **Step 3: Write minimal implementation**

```python
def archive_legacy_conf_tree(hypr_dir: Path) -> None:
    legacy_dir = hypr_dir / ".legacy"
    legacy_dir.mkdir(exist_ok=True)
    for path in hypr_dir.glob("*.conf"):
        path.replace(legacy_dir / path.name)
    source_dir = hypr_dir / "source"
    user_dir = hypr_dir / "user-configs"
    for path in list(source_dir.glob("*.conf")) + list(user_dir.glob("*.conf")):
        rel_parent = path.parent.relative_to(hypr_dir)
        target_parent = legacy_dir / rel_parent
        target_parent.mkdir(parents=True, exist_ok=True)
        path.replace(target_parent / path.name)
```

- [ ] **Step 4: Run final verification**

Run: `pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py \
        cloudyy_scripts/cloud-center-v2/cloud-center.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py \
        .config/hypr
git commit -m "feat: archive legacy hypr conf tree after lua cutover"
```

---

## Self-Review Notes

### Spec coverage

- **Architecture/layout** is covered by Tasks 1-3 and Task 7.
- **Explicit activation logic in `hyprland.lua`** is covered by Tasks 1, 3, 4, and 5.
- **Cloud Center Lua-native managers** are covered by Tasks 3-6.
- **One-time migration and `.legacy/` archive** is covered by Task 7.
- **Validation/idempotence** is covered by tests in Tasks 1, 3, 4, 5, 6, and the full verification step in Task 7.

### Placeholder scan

- No `TODO`, `TBD`, or "similar to previous task" placeholders remain.
- Each code-writing step includes concrete code to start from.
- Each test step includes an exact command and expected outcome.

### Type consistency

- Shared helper names stay consistent across tasks: `module_paths`, `ensure_user_override_active`, `ensure_source_active`, `archive_legacy_conf_tree`.
- The runtime convention is consistent across tasks: `source.<surface>` and `user-configs.user_<surface>`.
