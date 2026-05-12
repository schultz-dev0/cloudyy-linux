# Total Lua Migration — Design Spec

**Date:** 2026-05-12  
**Status:** Approved in chat — ready for written review

---

## Overview

Migrate the active Hyprland configuration and Cloud Center's Hyprland-facing internals to a
Lua-only runtime for Hyprland 0.55+, while preserving the existing configuration model:

- `hyprland.lua` remains a thin entrypoint that only activates modules
- `source/` remains the distro default config layer
- `user-configs/` remains the user / Cloud Center override layer
- legacy `.conf` files move to `.config/hypr/.legacy/` once cutover is complete

This is a format migration and runtime migration, not a structural redesign of the config tree.
The post-migration system should keep the current categories, readability, and override semantics.

Out of scope for Lua conversion:

- `hypridle.conf`
- `hyprlock.conf`
- `xdph.conf`

These remain separate `.conf` sidecars because Hyprland's ecosystem tools still use their own
config-file formats.

---

## Chosen Approach

Use a **phased internal migration with one final cutover**.

This avoids a big-bang rewrite while still ending with a clean system: after cutover, Cloud Center
no longer supports the legacy `.conf` runtime for live Hyprland config management.

Alternatives considered:

1. **Big-bang rewrite** — faster conceptually, but too risky for config migration and Cloud Center wiring.
2. **Thin adapter bridge with long-term dual support** — easier in the short term, but leaves the final
   system more complex and keeps legacy behavior alive.

The chosen approach allows translation and validation in phases while still enforcing a clean final
state: one active runtime, one persistence model, one set of managers.

---

## Architecture and File Layout

`~/.config/hypr/hyprland.lua` stays a thin switchboard, equivalent in purpose to the old
`hyprland.conf`: it activates modules in order and does not become a monolithic configuration file.

The active layout remains:

- `source/` — distro defaults
- `user-configs/` — user-edited or Cloud Center-managed overrides
- `.legacy/` — archived pre-Lua configs after cutover

The migration preserves the current mental model:

- defaults live in `source/`
- overrides live in `user-configs/`
- once a user override is activated for a config surface, the default file for that surface is
  no longer the active mutable source

Each current config surface keeps its original category boundary and style. The Lua version of the
tree should remain categorized, readable, and clean, rather than collapsing multiple surfaces into
large generic files.

Expected result:

- `source/*.conf` becomes `source/*.lua`
- `user-configs/*.conf` becomes `user-configs/*.lua`
- `hyprland.lua` requires active source/user-config modules in the same conceptual order currently
  used by `hyprland.conf`

---

## Runtime Behavior and Activation Logic

Lua activation should be explicit, not precedence-driven.

The current `.conf` flow depends on a combination of source order and override files. In the Lua
runtime, Cloud Center should instead manage **exact activation lines** in `hyprland.lua`.

For a managed surface such as bindings:

```lua
-- require("source.bindings")
require("user-configs.user_bindings") -- managed by Cloud Center
```

Activation rules:

1. Search `hyprland.lua` for the exact module line corresponding to the default config surface.
2. Comment or uncomment that line as needed.
3. Ensure the matching `user-configs.user_<surface>` require line exists with a Cloud Center marker.
4. Preserve surrounding file structure and category ordering.

This replaces "newest line wins" logic with exact module selection.

Ownership remains:

- `source/*.lua` is distro-owned
- `user-configs/*.lua` is user / Cloud Center-owned
- Cloud Center may create, activate, replace, or remove `user-configs/*.lua`
- Cloud Center must not rewrite distro defaults in `source/*.lua`

This makes the active source for each surface obvious from `hyprland.lua`, while keeping the
override model familiar.

---

## Cloud Center Responsibilities

Cloud Center behavior should stay functionally the same, but become Lua-native.

Required Lua-backed replacements:

- config manager for `source/*.lua` and `user-configs/*.lua`
- keybind manager for Lua binding modules
- Lua persistence / activation helper to replace the current `.conf`-oriented `hypr_persist.sh` flow
- Lua-aware handling for:
  - look-and-feel
  - animations
  - input
  - monitors
  - rules/startup
  - bindings

Cloud Center must edit override files and loader activation lines, not distro default module content.

The finished app must stop relying on:

- `hyprland.conf`
- `user-configs/*.conf`
- legacy `.conf` parsers/managers used only for the old runtime

---

## Migration Shape

The migration proceeds in four phases.

### Phase 1: File Translation

Translate active Hyprland config surfaces from `.conf` to Lua while preserving:

- current category boundaries
- current readability/style
- current split between defaults and overrides

This phase is about equivalence, not redesign.

### Phase 2: Cloud Center Lua Infrastructure

Replace `.conf`-specific internals with Lua-aware ones:

- Lua config manager wiring
- Lua keybind manager wiring
- Lua persistence/activation helper behavior
- Lua parsing/writing for the managed surfaces

### Phase 3: Migration and Activation

Provide a one-time migration path that:

- reads current active `.conf` state
- writes equivalent Lua files into `source/` and `user-configs/`
- updates `hyprland.lua` to activate the correct Lua modules
- preserves existing user overrides instead of flattening them back into distro defaults

### Phase 4: Final Cutover

Once the Lua runtime and Lua-backed Cloud Center surfaces are complete:

- stop using `hyprland.conf` as the live Hyprland runtime path
- stop reading/writing active `.conf` override files for Hyprland config management
- move legacy `.conf` files into `.config/hypr/.legacy/`
- remove Cloud Center wiring that exists only for the `.conf` runtime

After cutover, the active runtime is only:

- `hyprland.lua`
- `source/*.lua`
- `user-configs/*.lua`

---

## Migration Rules

The migration must follow these rules:

1. Never delete old `.conf` files during translation.
2. Only move legacy `.conf` files into `.legacy/` after the Lua runtime is confirmed.
3. Do not silently merge unrelated config surfaces.
4. Preserve user overrides when they exist.
5. If a config surface cannot be translated cleanly, block cutover for that surface instead of guessing.

The active files after migration must still look like normal hand-maintained config modules, not a
machine-generated dump.

---

## Safety and Idempotence

Loader edits in `hyprland.lua` must be exact-line targeted.

Requirements:

- no duplicate require lines
- no drifting comment markers
- no accidental category reordering
- no repeated edits that slowly degrade readability

Repeated apply operations must be idempotent: re-running the same Cloud Center action should leave
the file in the same state.

Cloud Center-managed lines in `hyprland.lua` should be:

- easy to search for
- easy to diff
- easy to toggle safely

---

## Validation Before Cutover

Cutover is allowed only when these are true:

1. The translated Lua runtime reproduces the currently active Hypr behavior.
2. Cloud Center edits the correct Lua files and toggles the correct loader lines.
3. Repeated reloads and repeated apply operations do not accumulate duplicate activation lines or
   break module ordering.
4. The active runtime no longer depends on `hyprland.conf`, active `user-configs/*.conf`, or
   legacy `.conf`-only managers.

At that point, `.legacy/` is archival only and every live Hyprland edit path goes through Lua.

---

## Deliverable Summary

The finished migration delivers:

- a Lua-only Hyprland runtime
- the same source-vs-user override model you already use
- Cloud Center editing Lua overrides and explicit loader activation lines
- a clean archived legacy `.conf` tree under `.config/hypr/.legacy/`
- no permanent dual-runtime support after cutover
