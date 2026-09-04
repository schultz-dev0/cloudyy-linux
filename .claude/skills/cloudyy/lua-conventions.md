# Lua Conventions (`.config/hypr/`)

## Structure: one file per module, seeded once

Every module is a single live file, `~/.config/hypr/<name>.lua` (`bindings`, `lookandfeel`, `animations`, `input`, `cursor`, `monitors`, `autostart`, `windowrules`, `variables`, `colors`) — gitignored, never tracked. `install/default-theme/hypr/<name>.lua` is the tracked seed; `deploy-dotfiles.sh` copies it to the live path once, only if the live file doesn't exist yet, then never touches it again. There's no distro-vs-override split and no toggle to check — the live file just *is* the config, edited in place from then on.

`hyprland.lua` is static: a flat, unconditional `require("<name>")` per module. It's seeded the same way and nothing ever rewrites its require lines.

**Marker/sentinel conventions vary by module** — pick the pattern matching what you're editing, not the closest-looking one:

| Module(s) | Sentinel | Markers | Owner |
|---|---|---|---|
| `lookandfeel`, `animations`, `input` | `-- @cloud-center-state = {json}` | `-- --- Cloud Center managed <surface> settings ---` | `hypr_layout_persist.py` / `hypr_animations_persist.py` |
| `cursor` | same sentinel format | `-- --- Cloud Center managed cursor settings ---` | `ccd/cursor.py` (its own schema, a superset of the other three) |
| `windowrules`, `autostart`, `variables` | `-- @cloud-center-rules-startup-state = {json}` | `-- --- Cloud Center managed additions ---` (generic, shared) | `rules_startup_page.py` |
| `bindings` | none (parsed straight from the Lua) | `-- --- Cloud Center Additions (managed by Cloud Center) ---` | `keybind_manager_lua.py` |
| `monitors`, `colors` | none | none — hand-parsed raw `hl.monitor(...)` lines / a pure matugen reader | `monitor_editor.py` / `ccd/monitors.py` |

Don't hand-edit inside a managed-markers region expecting it to persist — Cloud Center owns that span and rewrites it wholesale on the next apply.

**Two different "reset" operations, don't confuse them:** `hcm_lua.reset_to_default(module)` whole-file-replaces from the shipped seed (coarse — for `lookandfeel`/`input`/`animations` specifically, the seed ships *populated* personal defaults, not empty ones). `hypr_layout_persist.reset_page()` / `hypr_animations_persist.clear_key()` surgically clear specific keys, leaving the managed block empty and falling back to the static body. Same module, genuinely different results — see the docstrings on both for the full rationale.

## `hl.*` API

- **`hl.bind(keys, dispatcher, opts)`** — options table fields: `desc`/`description`, `repeating`, `locked`, `release`, `non_consuming`, `transparent`, `ignore_mods`, `dont_inhibit`, `long_press`, `submap_universal`, `click`, `drag`, `device`.
  ```lua
  hl.bind(mainMod .. " + W", hl.dsp.window.close(), { desc = "Kill active window" })
  hl.bind("Super_L", hl.dsp.exec_cmd("quickshell ipc call overview release"),
      { desc = "...", release = true, transparent = true, ignore_mods = true })
  ```
- **`hl.window_rule({ name, match = {class=..., title=...}, float, size, center, opaque, move, no_focus, suppress_event, opacity })`** — the type stub in `meta/hl.meta.lua` only documents `enabled/match/name`; real usage takes many more free-form effect keys than the stub shows, so don't trust the stub as exhaustive.
- **`hl.layer_rule({ name, match = {namespace=...}, blur, ignore_alpha, animation })`**.
- **`hl.on("hyprland.start", function() ... end)`** — wraps startup `hl.exec_cmd(...)` calls.
- **`hl.exec_cmd(cmd)`** — used both directly inside `hl.on` blocks and as a dispatcher inside `hl.dsp.exec_cmd(...)` for keybinds.
- **`hl.env(name, value)`** — environment variables, e.g. `hl.env("BROWSER", browser)`.

## The `desc` field is load-bearing, not decorative

Every `hl.bind()` call in `bindings.lua` includes `desc = "..."` — 100% coverage, no exceptions. Cloud Center's Keybind Manager parses this via regex (`keybind_manager_lua.py`) to populate its UI. **Any new keybind must include a clear `desc`** — this is a machine-readable field a real UI depends on, not just documentation.

## Naming

- `window_rule`/`layer_rule` `name` fields: kebab-case or bare app names for window rules (`"zen-browser"`, `"Steam"`, `"mpv"`); `quickshell_<name>` snake_case specifically for quickshell layer rules (`quickshell_bar_vignette`, `quickshell_panel`).
- Standard locals reused for every keybind that shells out: `local mainMod = "SUPER"`, `local scripts = os.getenv("HOME") .. "/cloudyy_scripts"`.

## Section headers

Consistent divider comment style for organizing long files:
```lua
-- ── Section Name ───────────────────────────────────────────────────────────
```
Used consistently in `bindings.lua` and `windowrules.lua` — match it when adding a new section rather than using a different comment style.
