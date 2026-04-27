#!/usr/bin/env bash
# =============================================================================
# select-shell-stack.sh — interactive shell-stack picker
# =============================================================================
# Prompts the user to choose a shell stack profile (defined in
# shell-stack.conf) and persists the selection to ${STATE_DIR}/shell-stack.
# Then invokes apply-shell-stack.sh to write ~/.config/hypr/source/shell-stack.conf.
#
# Can run standalone or as a phase of install.sh.
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${STATE_DIR:-${HOME}/.local/share/cloudyy}"
readonly STATE_FILE="${STATE_DIR}/shell-stack"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/shell-stack.conf"

if [[ -t 1 ]]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' CYAN=$'\e[1;36m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m' RESET=$'\e[0m'
else
  BOLD='' DIM='' CYAN='' GREEN='' YELLOW='' RESET=''
fi

mkdir -p "$STATE_DIR"

# --- read current selection (if any) -----------------------------------------
current=""
[[ -f "$STATE_FILE" ]] && current="$(<"$STATE_FILE")"

# --- print menu --------------------------------------------------------------
printf '\n%s%sShell stack selection%s\n' "$BOLD" "$CYAN" "$RESET"
printf '%s%s%s\n\n' "$DIM" "Pick which user-facing shell components to install." "$RESET"

i=1
default_idx=1
for p in "${PROFILES[@]}"; do
  name_var="PROFILE_${p}_NAME"
  desc_var="PROFILE_${p}_DESC"
  marker=" "
  if [[ -n "$current" && "$current" == "$p" ]]; then
    marker="*"; default_idx=$i
  elif [[ -z "$current" && "$p" == "$DEFAULT_PROFILE" ]]; then
    default_idx=$i
  fi
  printf '  %s%d.%s %s%s%s\n' "$BOLD" "$i" "$RESET" "$BOLD" "${!name_var}" "$RESET"
  printf '       %s%s%s\n' "$DIM" "${!desc_var}" "$RESET"
  printf '       %s[%s] active\n' "$marker" "$marker"
  ((i++))
done
echo

# --- prompt ------------------------------------------------------------------
read -rp "Selection [${default_idx}]: " sel
sel="${sel:-$default_idx}"
if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#PROFILES[@]} )); then
  printf '%sInvalid selection.%s\n' "$YELLOW" "$RESET" >&2
  exit 1
fi
chosen="${PROFILES[$((sel-1))]}"

# --- persist & apply ---------------------------------------------------------
echo "$chosen" >"$STATE_FILE"
printf '%s[✓]%s Saved selection: %s%s%s\n' "$GREEN" "$RESET" "$BOLD" "$chosen" "$RESET"

if [[ -x "${SCRIPT_DIR}/apply-shell-stack.sh" ]]; then
  bash "${SCRIPT_DIR}/apply-shell-stack.sh" "$chosen"
else
  printf '%s[!]%s apply-shell-stack.sh not found or not executable.\n' "$YELLOW" "$RESET"
fi
