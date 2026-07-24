---
name: cloudyy
description: Use when working in ~/cloudyy-linux and a change needs to reach the main branch (generic, ships-to-everyone) while the working directory is on personal (daily-driver branch) — or before running git checkout/stash to switch branches in this repo, or when unsure whether an edit belongs on main, personal, or both.
---

# Cloudyy Worktree Workflow

## Overview

`~/cloudyy-linux` is symlinked into the live desktop config (`~/.config/*` point into it) and stays on the `personal` branch permanently. A second, **permanent** worktree already exists at `~/cloudyy-linux-main`, permanently on `main`. Never `git checkout` between branches in either directory — that's what the other directory is for.

**Don't create a new temporary worktree with `git worktree add`.** `~/cloudyy-linux-main` already exists — `cd` into it and use it directly.

## Why this exists

Branch-switching on `~/cloudyy-linux` to promote a generic fix to `main` used to mean: stash, checkout main, apply, commit, checkout personal, cherry-pick back. This was error-prone (unrelated branch divergence surfaces as spurious conflicts) and briefly changed what Hyprland/Cloud Center see as the active config mid-edit, since `~/.config/*` is symlinked into whichever branch this checkout happens to be on at that moment.

## Which directory for what

| Change | Where |
|---|---|
| Personal daily-driver tweaks, `user-configs/*` edits, anything Cloud-Center-managed | `~/cloudyy-linux` (personal) only |
| Bug fix or feature meant for every install (not a personal preference) | Both — test in personal, land the commit in `~/cloudyy-linux-main` (main) too |

CLAUDE.md's branch-strategy note says edits to `source/autostart.lua`, `source/windowrules.lua`, `source/bindings.lua` are "typically personal-only by convention" — that's about day-to-day personal tinkering (adding your own keybind), not a blanket rule. A feature explicitly meant to ship to every install (e.g. new autostart entry for a generic feature) still needs to land on main even if it touches these files.

## How to promote a change from personal to main

1. Finish and verify the change in `~/cloudyy-linux` (personal) as normal. Commit it there (with the user's explicit go-ahead, per standing commit policy).
2. `cd ~/cloudyy-linux-main` — already on `main`, already up to date, do not `git worktree add` a new one.
3. `git cherry-pick <sha>` (the commit from personal). Expect conflicts only where the two branches' versions of the touched files genuinely differ for unrelated reasons — resolve by keeping the fix's intent, not personal's unrelated drift.
4. Review the diff, then ask for explicit approval before committing/pushing on main — same commit policy applies here as everywhere else.
5. Return to `~/cloudyy-linux` (personal) — it never moved, nothing to restore.

## Watch out for: skip-worktree files

`.config/zsh/.zshrc` and `cloudyy_scripts/theme_controller.sh` have git's skip-worktree bit set (`git ls-files -v | grep '^S'` to check for more). Local edits to these are **invisible** to `git status`/`diff`/`add` — a real edit can sit uncommitted indefinitely with no warning, exactly like it did once already. If you need to change one:

```
git update-index --no-skip-worktree <path>   # lift it
# ...edit, git add, commit...
git update-index --skip-worktree <path>      # restore it
```

These files are intentionally seed-once: the repo ships a generic version, and ongoing local drift on an already-installed machine isn't meant to be tracked. Don't remove the flag permanently without asking — that changes the intended behavior for every future install, not just this one.

## Quick reference

| Task | Command |
|---|---|
| Promote a personal commit to main | `cd ~/cloudyy-linux-main && git cherry-pick <sha>` |
| Check for skip-worktree landmines | `git ls-files -v \| grep '^S'` |
| Edit a skip-worktree file | `git update-index --no-skip-worktree <path>` first, restore after |
| Confirm which branch/directory you're in | `pwd && git branch --show-current` |
