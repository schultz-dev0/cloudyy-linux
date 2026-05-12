# Dev Branch Lua Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the current `dev` checkout at `/home/schultz/cloudyy-linux` to the same Lua-based Hyprland and Cloud Center config stack already working in `total-lua-migration`, without disturbing unrelated local edits.

**Architecture:** Treat `total-lua-migration` as the source of truth and port only the migration-related Hyprland and Cloud Center files into `dev`. Keep the existing `source/` vs `user-configs/` Lua override model, preserve non-Hypr sidecar `.conf` files (`hypridle.conf`, `hyprlock.conf`, `xdph.conf`), and archive only the legacy Hypr runtime `.conf` files after the ported code verifies cleanly.

**Tech Stack:** Hyprland 0.55 Lua config, Python 3, GTK4/Libadwaita Cloud Center, pytest, shell symlink management

---

## File Structure

- **Modify:** `.config/hypr/hyprland.lua` — switch the `dev` checkout to the Lua module loader used by the migrated worktree.
- **Modify/Create:** `.config/hypr/source/*.lua` — port the migrated Lua default modules (`variables`, `monitors`, `lookandfeel`, `animations`, `input`, `autostart`, `windowrules`, `bindings`, `colors`).
- **Modify/Create:** `.config/hypr/user-configs/*.lua` — port the migrated Cloud Center-managed Lua override files.
- **Preserve:** `.config/hypr/hypridle.conf`, `.config/hypr/hyprlock.conf`, `.config/hypr/xdph.conf` — out-of-scope sidecars.
- **Modify:** `cloudyy_scripts/cloud-center-v2/cloud-center.py` — keep the Lua page routing already proven in the migration worktree.
- **Modify:** `cloudyy_scripts/cloud-center-v2/hypr_persist.sh` — keep the Lua-backed entrypoint.
- **Modify:** `cloudyy_scripts/cloud-center-v2/config.yaml` — keep Lua-oriented comments and behaviors.
- **Modify:** `cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py` — loader toggles + one-time archive helper.
- **Modify:** `cloudyy_scripts/cloud-center-v2/lib/hypr_persist_lua.py` — Lua persistence + cutover wiring.
- **Modify:** `cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py`, `lib/keybind_manager_lua.py`, `lib/monitor_editor.py`, `lib/rules_startup_page.py` — Lua-native Cloud Center managers.
- **Modify/Create:** `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`, `test_hcm_lua.py`, `test_keybind_manager_lua.py`, `test_hypr_persist_lua.py`, `test_monitor_editor_lua.py`, `test_rules_startup.py`, `test_rules_startup_lua.py` — migration regression coverage.
- **Do not touch:** unrelated dirty files already present in `dev`, including `.config/quickshell/*`, `cloudyy_scripts/cloud-center-v2/lib/bluetooth_page.py`, and non-migration files outside the paths above.

### Task 1: Port the Hyprland Lua runtime tree into `dev`

**Files:**
- Modify: `.config/hypr/hyprland.lua`
- Modify/Create: `.config/hypr/source/colors.lua`
- Modify/Create: `.config/hypr/source/variables.lua`
- Modify/Create: `.config/hypr/source/monitors.lua`
- Modify/Create: `.config/hypr/source/lookandfeel.lua`
- Modify/Create: `.config/hypr/source/animations.lua`
- Modify/Create: `.config/hypr/source/input.lua`
- Modify/Create: `.config/hypr/source/autostart.lua`
- Modify/Create: `.config/hypr/source/windowrules.lua`
- Modify/Create: `.config/hypr/source/bindings.lua`
- Modify/Create: `.config/hypr/user-configs/user_variables.lua`
- Modify/Create: `.config/hypr/user-configs/user_lookandfeel.lua`
- Modify/Create: `.config/hypr/user-configs/user_animations.lua`
- Modify/Create: `.config/hypr/user-configs/user_input.lua`
- Modify/Create: `.config/hypr/user-configs/user_cursor.lua`
- Modify/Create: `.config/hypr/user-configs/user_bindings.lua`
- Modify/Create: `.config/hypr/user-configs/user_monitors.lua`
- Modify/Create: `.config/hypr/user-configs/user_rules_startup.lua`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`

- [ ] **Step 1: Write the failing Hypr runtime regressions into `dev`**

```python
def test_source_colors_bridge_is_explicit():
    colors_bridge = (HYPR_DIR / "source/colors.lua").read_text(encoding="utf-8")
    lookandfeel = (HYPR_DIR / "source/lookandfeel.lua").read_text(encoding="utf-8")
    assert '.hyprlua/colors.lua' in colors_bridge
    assert 'dofile(' in colors_bridge
    assert 'require("source.colors")' in lookandfeel
    assert 'require("colors")' not in lookandfeel
    assert 'return require("colors")' not in colors_bridge


def test_source_lookandfeel_omits_removed_dwindle_pseudotile_key():
    lookandfeel = (HYPR_DIR / "source/lookandfeel.lua").read_text(encoding="utf-8")
    assert "pseudotile" not in lookandfeel


def test_user_lookandfeel_does_not_emit_invalid_stayfocused_field():
    user_lookandfeel = (HYPR_DIR / "user-configs/user_lookandfeel.lua").read_text(encoding="utf-8")
    assert "stayfocused" not in user_lookandfeel


def test_source_bindings_live_text_extract_uses_valid_key_string():
    bindings = (HYPR_DIR / "source/bindings.lua").read_text(encoding="utf-8")
    assert 'mainMod .. " + SHIFT + E"' in bindings
    assert 'mainMod .. " SHIFT + E"' not in bindings
```

- [ ] **Step 2: Run the runtime tests to verify they fail on `dev`**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q
```

Expected: FAIL because the current `dev` checkout still contains the old `.hyprlua` entrypoint and/or the pre-fix Lua files.

- [ ] **Step 3: Port the runtime files from the migration worktree**

Run:

```bash
cd /home/schultz/cloudyy-linux
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/.config/hypr/hyprland.lua .config/hypr/hyprland.lua
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/.config/hypr/source/*.lua .config/hypr/source/
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/.config/hypr/user-configs/*.lua .config/hypr/user-configs/
```

Key content that must land in `dev`:

```lua
package.path = package.path
    .. ";" .. home .. "/.config/hypr/?.lua"
    .. ";" .. home .. "/.config/hypr/source/?.lua"
    .. ";" .. home .. "/.config/hypr/user-configs/?.lua"
    .. ";" .. home .. "/.config/hypr/.hyprlua/?.lua"

-- require("source.variables")
-- require("source.monitors")
-- require("source.lookandfeel")
require("source.animations")
-- require("source.input")
require("source.autostart")
require("source.windowrules")
require("source.bindings")
```

and:

```lua
-- Explicit bridge to the shared color loader while Task 2 still relies on
-- the existing .hyprlua implementation.
return dofile(os.getenv("HOME") .. "/.config/hypr/.hyprlua/colors.lua")
```

- [ ] **Step 4: Run the runtime tests to verify they pass**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py -q
```

Expected: PASS

- [ ] **Step 5: Commit the runtime tree port**

```bash
cd /home/schultz/cloudyy-linux
git add .config/hypr/hyprland.lua .config/hypr/source/*.lua .config/hypr/user-configs/*.lua cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py
git commit -m "feat: port hypr runtime to lua on dev"
```

### Task 2: Port the Lua-aware Cloud Center code and regression tests into `dev`

**Files:**
- Modify: `cloudyy_scripts/cloud-center-v2/cloud-center.py`
- Modify: `cloudyy_scripts/cloud-center-v2/hypr_persist.sh`
- Modify: `cloudyy_scripts/cloud-center-v2/config.yaml`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py`
- Modify: `cloudyy_scripts/cloud-center-v2/lib/hypr_persist_lua.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py`
- Modify/Create: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py`

- [ ] **Step 1: Write or port the failing Cloud Center Lua tests into `dev`**

Ensure `dev` contains the same migration regression tests already proven in the worktree, including these exact assertions:

```python
def test_main_archives_legacy_conf_tree_on_first_persist(tmp_path):
    rc = hypr_persist_lua.main(["hypr_persist_lua", "general:gaps_in", "8", str(hypr)])
    assert rc == 0
    assert (hypr / ".legacy" / "hyprland.conf").exists()


def test_monitor_editor_writes_user_monitors_lua(tmp_path):
    content = (hypr / "user-configs" / "user_monitors.lua").read_text(encoding="utf-8")
    assert 'hl.monitor({' in content


def test_rules_startup_serializes_env_as_lua():
    assert 'hl.env("FOO", "bar")' in rendered
```

- [ ] **Step 2: Run the focused Lua manager tests to verify they fail on `dev`**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest \
  cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q
```

Expected: FAIL because `dev` still contains the old `.conf`-oriented manager code.

- [ ] **Step 3: Port the Cloud Center migration files from the worktree**

Run:

```bash
cd /home/schultz/cloudyy-linux
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/cloud-center.py cloudyy_scripts/cloud-center-v2/cloud-center.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/hypr_persist.sh cloudyy_scripts/cloud-center-v2/hypr_persist.sh
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/config.yaml cloudyy_scripts/cloud-center-v2/config.yaml
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/lib/hypr_persist_lua.py cloudyy_scripts/cloud-center-v2/lib/hypr_persist_lua.py
cp /home/schultz/cloudyy-linux/.worktrees/total-lua-migration/cloudyy_scripts/cloud-center-v2/tests/test_*.py cloudyy_scripts/cloud-center-v2/tests/
```

Critical post-port content that must exist in `dev`:

```python
MONITORS_CONF = HYPR_DIR / "user-configs" / "user_monitors.lua"
```

```python
from lib.hyprlua_runtime import archive_legacy_conf_tree, ensure_source_active, ensure_user_override_active
```

```python
archive_legacy_conf_tree(hypr_dir)
```

- [ ] **Step 4: Run the focused Lua manager tests to verify they pass**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest \
  cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q
```

Expected: PASS

- [ ] **Step 5: Commit the Cloud Center Lua port**

```bash
cd /home/schultz/cloudyy-linux
git add cloudyy_scripts/cloud-center-v2/cloud-center.py \
        cloudyy_scripts/cloud-center-v2/hypr_persist.sh \
        cloudyy_scripts/cloud-center-v2/config.yaml \
        cloudyy_scripts/cloud-center-v2/lib/hcm_lua.py \
        cloudyy_scripts/cloud-center-v2/lib/keybind_manager_lua.py \
        cloudyy_scripts/cloud-center-v2/lib/monitor_editor.py \
        cloudyy_scripts/cloud-center-v2/lib/rules_startup_page.py \
        cloudyy_scripts/cloud-center-v2/lib/hyprlua_runtime.py \
        cloudyy_scripts/cloud-center-v2/lib/hypr_persist_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py \
        cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py \
        cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py
git commit -m "feat: port cloud center lua config flow to dev"
```

### Task 3: Cut `dev` over locally and archive legacy Hypr runtime files

**Files:**
- Modify/Create: `.config/hypr/.legacy/**`
- Modify: `/home/schultz/.config/hypr` symlink target (environment state)
- Modify: `/home/schultz/cloudyy_scripts` symlink target (environment state)

- [ ] **Step 1: Write a failing environment check**

Run:

```bash
test "$(readlink -f /home/schultz/.config/hypr)" = "/home/schultz/cloudyy-linux/.config/hypr" &&
test "$(readlink -f /home/schultz/cloudyy_scripts)" = "/home/schultz/cloudyy-linux/cloudyy_scripts"
```

Expected: FAIL if the live environment is still pointed at the worktree.

- [ ] **Step 2: Point live symlinks back at the migrated `dev` checkout**

Run:

```bash
ln -sfn /home/schultz/cloudyy-linux/.config/hypr /home/schultz/.config/hypr
ln -sfn /home/schultz/cloudyy-linux/cloudyy_scripts /home/schultz/cloudyy_scripts
readlink -f /home/schultz/.config/hypr
readlink -f /home/schultz/cloudyy_scripts
```

Expected output:

```text
/home/schultz/cloudyy-linux/.config/hypr
/home/schultz/cloudyy-linux/cloudyy_scripts
```

- [ ] **Step 3: Run the archive helper against the `dev` checkout**

Run:

```bash
cd /home/schultz/cloudyy-linux/cloudyy_scripts/cloud-center-v2
python3 - <<'PY'
from pathlib import Path
from lib.hyprlua_runtime import archive_legacy_conf_tree
archive_legacy_conf_tree(Path('/home/schultz/cloudyy-linux/.config/hypr'))
PY
```

Expected output:

```text
[hypr_persist] archived ...
```

- [ ] **Step 4: Verify the archive contents and preserved sidecars**

Run:

```bash
find /home/schultz/cloudyy-linux/.config/hypr/source -maxdepth 1 -type f -name '*.conf' | sort
find /home/schultz/cloudyy-linux/.config/hypr/user-configs -maxdepth 1 -type f -name '*.conf' | sort
ls -1 /home/schultz/cloudyy-linux/.config/hypr/hypridle.conf \
      /home/schultz/cloudyy-linux/.config/hypr/hyprlock.conf \
      /home/schultz/cloudyy-linux/.config/hypr/xdph.conf
find /home/schultz/cloudyy-linux/.config/hypr/.legacy -type f | sort
```

Expected:
- first two commands show no legacy active `.conf` files
- sidecar files still exist at the Hypr root
- `.legacy/.archived` exists

- [ ] **Step 5: Commit the cutover state**

```bash
cd /home/schultz/cloudyy-linux
git add .config/hypr/.legacy .config/hypr
git commit -m "feat: archive legacy hypr conf tree on dev"
```

### Task 4: Run the full migration verification on `dev`

**Files:**
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py`
- Test: `cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py`

- [ ] **Step 1: Run the focused migration verification bundle**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest \
  cloudyy_scripts/cloud-center-v2/tests/test_hyprlua_runtime.py \
  cloudyy_scripts/cloud-center-v2/tests/test_hcm_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_keybind_manager_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_hypr_persist_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_monitor_editor_lua.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup.py \
  cloudyy_scripts/cloud-center-v2/tests/test_rules_startup_lua.py -q
```

Expected: PASS

- [ ] **Step 2: Run the full Cloud Center suite**

Run:

```bash
cd /home/schultz/cloudyy-linux
pytest cloudyy_scripts/cloud-center-v2/tests -q
```

Expected: PASS with the same benign GI warnings seen in the worktree.

- [ ] **Step 3: Run Hyprland live validation**

Run:

```bash
hyprctl reload
hyprctl configerrors
```

Expected:
- `reload` returns `ok`
- `configerrors` is empty

- [ ] **Step 4: Record the final branch state**

Run:

```bash
cd /home/schultz/cloudyy-linux
git --no-pager status --short
```

Expected: only the intended migration files remain changed; unrelated pre-existing dirty files remain untouched.

- [ ] **Step 5: Commit the verification checkpoint**

```bash
cd /home/schultz/cloudyy-linux
git add .config/hypr cloudyy_scripts/cloud-center-v2
git commit -m "test: verify dev lua cutover"
```

