---
name: cloudyy
description: Use when writing or editing any code in ~/cloudyy-linux — QML/quickshell, bash scripts, Python (Cloud Center backend), or Lua (Hyprland config) — to match this distro's existing conventions.
---

# Cloudyy

Reference for working on the cloudyy-linux distro: coding conventions already established across its QML, bash, Python, and Lua code. Read the relevant section(s) below before writing code — matching existing patterns beats inventing new ones.

`~/cloudyy-linux` is a single checkout on `main`, symlinked into the live desktop config (`~/.config/*` point into it). One branch, one directory — no worktree juggling, no personal/main promotion dance. (There used to be a separate `personal` branch and a permanent second worktree for cherry-picking fixes across them; both are gone as of 2026-07-25 — the whole reason for the split, `.config/hypr/`'s generic-vs-personal file layout, was eliminated in the same change. If you find a reference to `personal`, `cloudyy-linux-main`, or cherry-picking between them anywhere, it's stale — main is the only branch now.)

**Skip-worktree landmine:** a few files have git's skip-worktree bit set — local edits to these are **invisible** to `git status`/`diff`/`add`, so a real edit can sit uncommitted indefinitely with zero warning. Check current state with `git ls-files -v | grep '^S'` rather than trusting any hardcoded list (it drifts — `deploy-dotfiles.sh`'s `reapply_skip_worktree()` is the source of truth for which paths get the flag). To edit one: `git update-index --no-skip-worktree <path>`, edit/commit, then `git update-index --skip-worktree <path>` again to restore it — don't leave the flag off.

## Code conventions

Detailed, file:line-cited conventions per language live in separate reference files — read the one relevant to what you're touching:

- **QML / Quickshell** (`.config/quickshell/**`, `.config/OOBE/**`) → [qml-conventions.md](qml-conventions.md)
- **Bash** (`install/*.sh`, `cloudyy_scripts/**/*.sh`) → [bash-conventions.md](bash-conventions.md)
- **Python** (`cloudyy_scripts/cloud-center-v2/**`) → [python-conventions.md](python-conventions.md)
- **Lua** (`.config/hypr/**`) → [lua-conventions.md](lua-conventions.md)

Cross-language constants worth knowing regardless of which file you're touching:
- No `.editorconfig`/linter config exists anywhere in the repo — style is convention-by-example only, so grep for a similar existing pattern before inventing one.
- `.config/hypr/*.lua` is the one place "generic vs personal" still applies, and it's a seed-once split now, not a live-toggle: `install/default-theme/hypr/<name>.lua` is what a fresh install gets, `~/.config/hypr/<name>.lua` is the live, gitignored, hand/Cloud-Center-edited file — see lua-conventions.md for the full marker/sentinel taxonomy. `.zshrc`-style seed-once files use the skip-worktree mechanism instead (above), same idea, different mechanism.
