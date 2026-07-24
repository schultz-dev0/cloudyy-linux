# Bash Conventions

## Header / safety

- Shebang: always `#!/usr/bin/env bash`.
- `install/*.sh` scripts use `set -euo pipefail -E` (the `-E` makes ERR traps propagate into functions). Simpler scripts (`theme_controller.sh`, `cloud-center-v2/cloud-center`, some `install/*.sh`) use plain `set -euo pipefail`.
- Deliberate exception: `install/test-install.sh` uses `set -uo pipefail` (no `-e`) with a comment explaining why — a test runner shouldn't abort on the first failing test. That same file's regression suite greps other scripts for `set -euo pipefail` — this is an enforced, tested convention, not incidental style.
- Standard root guard: `[[ $EUID -eq 0 ]] && { log_error "Do not run as root."; exit 1; }`.

## Logging helpers

Every `install/*.sh` script (re-)defines its own copy of the same shape — TTY-aware colors, a `_ts()` timestamp helper, and `log()`/`log_ok()`/`log_warn()`/`log_error()`:

```bash
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi
_ts() { date '+%H:%M:%S'; }
log()      { printf '%s[*]%s  [%s] %s\n'  "$BLUE"  "$RESET" "$(_ts)" "$1"; }
log_ok()   { printf '%s[✓]%s  [%s] %s\n'  "$GREEN" "$RESET" "$(_ts)" "$1"; }
log_warn() { printf '%s[!]%s  [%s] %s\n'  "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error(){ printf '%s[✗]%s  [%s] %s\n'  "$RED"   "$RESET" "$(_ts)" "$1" >&2; }
```

`install/lib.sh` has the canonical version (plus `log_skip`, `log_section`, `divider`), but most `install/*.sh` scripts duplicate their own copy rather than sourcing it — only `hyprland-install.sh` actually sources `lib.sh`. Single-purpose scripts use a lighter one-liner variant instead, e.g. `theme_controller.sh`: `log() { printf '\033[1;34m[THEME]\033[0m %s\n' "$*" >&2; }`.

**When adding a new install script:** copy the standard block rather than sourcing `lib.sh` unless you're already touching `hyprland-install.sh` — matches existing precedent even though it's duplication.

## Parallelism

- Shell-level fan-out: `xargs -0 -P "$MAX_JOBS" -I {} bash -c 'fn "$@"' _ {}` (`_legacy-rofi/appearance.sh:56`, and the OOBE thumbnail-generation fix this session).
- Python-side equivalent: `ThreadPoolExecutor` (`cloud-center-v2/lib/ccd/model.py`, `bluetooth_core.py`).

## Singleton / instance detection

Two tiers, pick the one matching what you're detecting:
- Simple daemon check: `pgrep -x <name>` (fine for a single well-named daemon).
- Quickshell app instances: **do not** raw `pgrep -f qs` (it self-matches its own grep). Query `qs list --all -j` and parse with an inline `python3 -c` instead — explicitly documented in `cc-validate.sh` as "never raw pgrep". Reference implementation: `cloud-center-v2/cloud-center`'s `cloud_center_pids()` + `has_window()` functions.

## Notifications

Canonical shape, reused everywhere with only urgency/timeout varying:
```bash
notify() { notify-send "Component Name" "$1" -u "${2:-normal}" -t 3000 2>/dev/null || true; }
```
Always non-fatal (`|| true` or `2>/dev/null`), title = component name, message = `$1`, urgency defaults to `normal`.

## Naming

- Scripts: kebab-case (`deploy-dotfiles.sh`, `setup-quickshell-service.sh`). A leading underscore on a directory marks deprecated/legacy (`_legacy-rofi/`).
- Functions: snake_case (`pacman_install`, `has_window`, `read_state`).
- Leading-underscore prefix IS the convention for internal/private helpers in bash (opposite of the Python rule) — `_ts()`, `_err_handler()`, `_is_our_link()` are standard and expected.

## Error handling

- `install/*.sh` scripts use `trap '_err_handler' ERR` (relies on `set -euo pipefail -E`), where `_err_handler()` logs the failing line/command then lets `set -e` exit:
  ```bash
  _err_handler() { log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"; }
  trap '_err_handler' ERR
  ```
- Single-purpose scripts (`theme_controller.sh`) use a `die()` pattern instead: log, notify critical, `exit 1`.
- Optional/non-critical steps use soft-fail with explicit wording: `cmd || log_warn "... (non-fatal)"`.

## Shared library (`install/lib.sh`)

Guard against double-sourcing: `[[ -n "${_CLOUDYY_LIB_LOADED:-}" ]] && return 0`. Provides logging helpers, `pacman_install()`/`aur_install()` (batch-then-retry-individually), `link_aur_binary_to_local_bin()`/`verify_local_binary()`. Source with a guard-then-source pattern plus a shellcheck directive:
```bash
[[ -f "$LIB_FILE" ]] || { echo "lib.sh not found" >&2; exit 1; }
# shellcheck source=install/lib.sh
source "$LIB_FILE"
```
