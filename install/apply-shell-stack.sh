#!/usr/bin/env bash
# =============================================================================
# apply-shell-stack.sh — emits ~/.config/hypr/source/shell-stack.conf
# =============================================================================
# Reads a profile key from $1 (or ${STATE_DIR}/shell-stack) and writes the
# Hyprland sourced file containing the profile's exec-once entries.
# Idempotent.
#
# Package installation is NOT done here — that's the installer's job. This
# script is safe to re-run any time the user wants to swap profiles.
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${STATE_DIR:-${HOME}/.local/share/cloudyy}"
readonly STATE_FILE="${STATE_DIR}/shell-stack"
readonly HYPR_OUT="${HOME}/.config/hypr/source/shell-stack.conf"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/shell-stack.conf"

# --- determine profile -------------------------------------------------------
profile="${1:-}"
if [[ -z "$profile" && -f "$STATE_FILE" ]]; then
  profile="$(<"$STATE_FILE")"
fi
profile="${profile:-$DEFAULT_PROFILE}"

# --- validate ----------------------------------------------------------------
valid=0
for p in "${PROFILES[@]}"; do [[ "$p" == "$profile" ]] && valid=1; done
if (( ! valid )); then
  printf 'apply-shell-stack: unknown profile "%s"\n' "$profile" >&2
  printf 'available: %s\n' "${PROFILES[*]}" >&2
  exit 1
fi

# --- slot list (must mirror shell-stack.conf documentation) -----------------
SLOTS=(bar notifications launcher volume_osd app_menu power_menu)

# --- emit hypr fragment ------------------------------------------------------
mkdir -p "$(dirname "$HYPR_OUT")"
{
  printf '# =============================================================================\n'
  printf '# Shell stack autostart — managed by ~/cloudyy-linux/install/apply-shell-stack.sh\n'
  printf '# Edit ~/cloudyy-linux/install/shell-stack.conf to change profiles or add slots.\n'
  printf '# Re-run:   bash ~/cloudyy-linux/install/select-shell-stack.sh\n'
  printf '# =============================================================================\n'
  printf '# Active profile: %s\n\n' "$profile"

  for slot in "${SLOTS[@]}"; do
    impl_var="SLOT_${profile}_${slot}"
    exec_var="EXEC_${profile}_${slot}"
    impl="${!impl_var:-}"
    cmd="${!exec_var:-}"

    printf '# --- %s ---' "$slot"
    if [[ -n "$impl" ]]; then
      printf '   (impl: %s)\n' "$impl"
    else
      printf '   (slot reserved)\n'
    fi
    if [[ -n "$cmd" ]]; then
      printf 'exec-once = %s\n' "$cmd"
    fi
    printf '\n'
  done
} >"$HYPR_OUT"

printf '[✓] Wrote %s (profile: %s)\n' "$HYPR_OUT" "$profile"

# --- update theme_controller.sh wiring ---------------------------------------
if [[ -x "${SCRIPT_DIR}/widget_bridge.sh" ]]; then
  bash "${SCRIPT_DIR}/widget_bridge.sh" "$profile"
else
  printf '[!] widget_bridge.sh not found or not executable.\n' >&2
fi

# Ensure matugen generates the theme for the new shell stack immediately
# We look for theme_controller.sh in repo first, then home.
THEME_CONTROLLER="$(dirname "$SCRIPT_DIR")/cloudyy_scripts/theme_controller.sh"
[[ -f "$THEME_CONTROLLER" ]] || THEME_CONTROLLER="${HOME}/cloudyy_scripts/theme_controller.sh"

if [[ -x "$THEME_CONTROLLER" ]]; then
  printf '[*] Seeding theme for %s...\n' "$profile"
  "$THEME_CONTROLLER" restore >/dev/null 2>&1 || true
fi

# --- live reload if hyprland is running --------------------------------------
if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi
