# Lua Conventions (`.config/hypr/`)

## Structure & generic-vs-personal split

`install/default-theme/hyprland.lua` (what a fresh install gets) requires generic modules directly:
```lua
require("source.variables")
require("source.monitors")
...
require("source.bindings")
```
The live `.config/hypr/hyprland.lua` instead requires `user-configs.user_*` variants for most modules (`user_variables`, `user_autostart`, `user_windowrules`, `user_lookandfeel`, `user_animations`, `user_input`, `user_cursor`, `user_monitors`), each annotated `-- managed by Cloud Center`, with the corresponding `source.*` lines commented out (not deleted) rather than removed. **`require("source.bindings")` is the one module still sourced directly/generically** — there's no `user_bindings` override switch in the live file the way there is for the others.

`user_windowrules.lua` and `user_bindings.lua` carry Cloud Center marker comments delimiting machine-managed regions it rewrites via regex:
```lua
-- @cloud-center-rules-startup-state = {...}
-- --- Cloud Center Additions (managed by Cloud Center) ---
-- --- End Cloud Center Additions ---
```
Don't hand-edit inside these markers expecting it to persist — Cloud Center treats that region as its own.

**When adding a generic feature:** check which layer (`source/*.lua` vs the live `hyprland.lua`'s actual `require()`s) is actually active before assuming an edit takes effect — an already-customized machine may have switched a module over to its `user_*` override, silently making the generic `source/*.lua` edit inert on that machine (confirmed this exact gap during OOBE's autostart/windowrules work). Fresh installs always source `source/*.lua` directly per `install/default-theme/hyprland.lua`.

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

Every `hl.bind()` call in `source/bindings.lua` includes `desc = "..."` — 100% coverage, no exceptions. Cloud Center's Keybind Manager parses this via regex (`keybind_manager_lua.py`) to populate its UI. **Any new keybind must include a clear `desc`** — this is a machine-readable field a real UI depends on, not just documentation.

## Naming

- `window_rule`/`layer_rule` `name` fields: kebab-case or bare app names for window rules (`"zen-browser"`, `"OOBE"`, `"Steam"`); `quickshell_<name>` snake_case specifically for quickshell layer rules (`quickshell_bar_vignette`, `quickshell_panel`).
- Standard locals reused for every keybind that shells out: `local mainMod = "SUPER"`, `local scripts = os.getenv("HOME") .. "/cloudyy_scripts"`.

## Section headers

Consistent divider comment style for organizing long files:
```lua
-- ── Section Name ───────────────────────────────────────────────────────────
```
or, for smaller groups, a plain `-- Section` comment (e.g. `-- OOBE --`). Used consistently in `bindings.lua` and `windowrules.lua` — match it when adding a new section rather than using a different comment style.
