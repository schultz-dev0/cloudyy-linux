---
name: cloudyy
description: Use when writing or editing any code in ~/cloudyy-linux — QML/quickshell, bash scripts, Python (Cloud Center backend), or Lua (Hyprland config) — to match this distro's existing conventions, or when a change needs to reach the main branch while working on personal (daily-driver branch), or before running git checkout/stash to switch branches in this repo.
---

# Cloudyy

Reference for working on the cloudyy-linux distro: how the personal/main branch split works, and the coding conventions already established across its QML, bash, Python, and Lua code. Read the relevant section(s) below before writing code — matching existing patterns beats inventing new ones.

## Worktree workflow (branch/commit mechanics)

`~/cloudyy-linux` is symlinked into the live desktop config (`~/.config/*` point into it) and stays on the `personal` branch permanently. A second, **permanent** worktree already exists at `~/cloudyy-linux-main`, permanently on `main`. Never `git checkout` between branches in either directory — that's what the other directory is for.

**Don't create a new temporary worktree with `git worktree add`.** `~/cloudyy-linux-main` already exists — `cd` into it and use it directly.

**Why:** branch-switching on `~/cloudyy-linux` to promote a generic fix to `main` used to mean stash → checkout main → apply → commit → checkout personal → cherry-pick back — error-prone (unrelated branch divergence surfaces as spurious conflicts), and it briefly changed what Hyprland/Cloud Center see as the active config mid-edit, since `~/.config/*` is symlinked into whichever branch this checkout happens to be on.

| Change | Where |
|---|---|
| Personal daily-driver tweaks, `user-configs/*` edits, anything Cloud-Center-managed | `~/cloudyy-linux` (personal) only |
| Bug fix or feature meant for every install (not a personal preference) | Both — test in personal, land the commit in `~/cloudyy-linux-main` (main) too |

CLAUDE.md's branch-strategy note calls edits to `source/autostart.lua`/`windowrules.lua`/`bindings.lua` "typically personal-only by convention" — that's about day-to-day personal tinkering, not a blanket rule. A feature explicitly meant to ship to every install still needs to land on main even if it touches these files.

**To promote a change from personal to main:**
1. Finish and verify the change in `~/cloudyy-linux` (personal). Commit it there (with explicit user go-ahead — standing commit policy, ask every time).
2. `cd ~/cloudyy-linux-main` — already on `main`, already up to date.
3. `git cherry-pick <sha>`. Expect conflicts only where the branches' versions of the touched files genuinely differ for unrelated reasons — resolve by keeping the fix's intent, not personal's unrelated drift.
4. Review the diff, ask for explicit approval before committing/pushing on main too.
5. Return to `~/cloudyy-linux` — it never moved, nothing to restore.

**Skip-worktree landmine:** `.config/zsh/.zshrc` and `cloudyy_scripts/theme_controller.sh` have git's skip-worktree bit set (`git ls-files -v | grep '^S'` to check for more). Local edits to these are **invisible** to `git status`/`diff`/`add` — a real edit can sit uncommitted indefinitely with zero warning. To change one: `git update-index --no-skip-worktree <path>`, edit/commit, then `git update-index --skip-worktree <path>` again to restore it. These files are intentionally seed-once (generic version ships, local drift on an already-installed machine isn't meant to be tracked) — don't remove the flag permanently without asking.

**Quick reference:**

| Task | Command |
|---|---|
| Promote a personal commit to main | `cd ~/cloudyy-linux-main && git cherry-pick <sha>` |
| Check for skip-worktree landmines | `git ls-files -v \| grep '^S'` |
| Edit a skip-worktree file | `git update-index --no-skip-worktree <path>` first, restore after |
| Confirm which branch/directory you're in | `pwd && git branch --show-current` |

## Code conventions

Detailed, file:line-cited conventions per language live in separate reference files — read the one relevant to what you're touching:

- **QML / Quickshell** (`.config/quickshell/**`, `.config/OOBE/**`) → [qml-conventions.md](qml-conventions.md)
- **Bash** (`install/*.sh`, `cloudyy_scripts/**/*.sh`) → [bash-conventions.md](bash-conventions.md)
- **Python** (`cloudyy_scripts/cloud-center-v2/**`) → [python-conventions.md](python-conventions.md)
- **Lua** (`.config/hypr/**`) → [lua-conventions.md](lua-conventions.md)

Cross-language constants worth knowing regardless of which file you're touching:
- No `.editorconfig`/linter config exists anywhere in the repo — style is convention-by-example only, so grep for a similar existing pattern before inventing one.
- "Generic vs personal" is a repo-wide split, not just a git-branch thing: `install/default-theme/hyprland.lua` sources `source/*.lua` directly (what a fresh install gets); the live `.config/hypr/hyprland.lua` instead sources `user-configs/user_*.lua` (Cloud-Center-managed personal overrides) for everything except `source/bindings.lua`. Same generic/override split exists for `.zshrc`-style files via the skip-worktree mechanism above. When adding a generic feature, check which layer it needs to land in.
