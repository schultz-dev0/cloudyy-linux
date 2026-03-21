#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# switch_style.sh — Waybar preset switcher
#
# Deployment model:
#   config.jsonc → regular COPY into ~/.config/waybar/
#                  set_position.sh mutates this freely at runtime — the preset
#                  source is never touched after install.
#
#   style.css    → SYMLINK into ~/.config/waybar/presets/<name>/style.css
#                  Waybar's inotify watcher follows the symlink so CSS edits
#                  in the preset dir hot-reload without a full restart.
#
# For vertical presets, automatically re-applies the saved side preference
# (left or right) from ~/.config/waybar/.vertical_side, defaulting to left.
#
# Usage:  switch_style.sh <preset_name>
#         switch_style.sh --list
# -----------------------------------------------------------------------------

set -euo pipefail

readonly WAYBAR_DIR="${HOME}/.config/waybar"
readonly PRESETS_DIR="${WAYBAR_DIR}/presets"
readonly ACTIVE_CONFIG="${WAYBAR_DIR}/config.jsonc"
readonly ACTIVE_STYLE="${WAYBAR_DIR}/style.css"
readonly CURRENT_PRESET_FILE="${WAYBAR_DIR}/.current_preset"
readonly VERTICAL_SIDE_FILE="${WAYBAR_DIR}/.vertical_side"
readonly CURRENT_POSITION_FILE="${WAYBAR_DIR}/.current_position"

# ── Helpers ──────────────────────────────────────────────────────────────────

die() {
  printf '[switch_style] ERROR: %s\n' "$*" >&2
  exit 1
}
info() { printf '[switch_style] %s\n' "$*" >&2; }

list_presets() {
  info "Available presets:"
  for d in "${PRESETS_DIR}"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    current=""
    [[ -f "${CURRENT_PRESET_FILE}" ]] && [[ "$(cat "${CURRENT_PRESET_FILE}")" == "$name" ]] &&
      current=" (active)"
    printf '  • %s%s\n' "$name" "$current" >&2
  done
}

# ── Argument handling ─────────────────────────────────────────────────────────

if [[ "${1:-}" == "--list" ]]; then
  list_presets
  exit 0
fi

PRESET="${1:-}"

if [[ -z "$PRESET" ]]; then
  printf 'Usage: %s <preset_name>\n       %s --list\n' "$0" "$0" >&2
  list_presets
  exit 1
fi

# ── Validate preset ───────────────────────────────────────────────────────────

PRESET_DIR="${PRESETS_DIR}/${PRESET}"

[[ -d "${PRESET_DIR}" ]] || die "Preset '${PRESET}' not found at ${PRESET_DIR}"
[[ -f "${PRESET_DIR}/config.jsonc" ]] || die "Preset '${PRESET}' missing config.jsonc"
[[ -f "${PRESET_DIR}/style.css" ]] || die "Preset '${PRESET}' missing style.css"

info "Switching to preset: ${PRESET}"

# ── config.jsonc — atomic copy (runtime-mutable, never touches preset source) ─

TMP_CONFIG="$(mktemp "${WAYBAR_DIR}/.config.XXXXXX.jsonc")"
cleanup() { rm -f "${TMP_CONFIG}"; }
trap cleanup EXIT

cp "${PRESET_DIR}/config.jsonc" "${TMP_CONFIG}"
mv "${TMP_CONFIG}" "${ACTIVE_CONFIG}"

info "Copied:    config.jsonc ← ${PRESET_DIR}/config.jsonc"

# ── style.css — file copy (modifies the real style.css inode so inotify fires) ─
# WHY NOT SYMLINK: waybar's reload_style_on_change watches the RESOLVED inode
# (the symlink's current target). Doing `ln -sf new_preset/style.css style.css`
# changes where the symlink points but does NOT modify the old target's inode —
# so inotify never fires and waybar silently keeps the old CSS.
# A cp -f writes directly to the ~/.config/waybar/style.css inode that waybar
# is already watching, which correctly triggers reload_style_on_change.

cp -f "${PRESET_DIR}/style.css" "${ACTIVE_STYLE}"

info "Copied:    style.css    ← ${PRESET_DIR}/style.css"

echo "${PRESET}" >"${CURRENT_PRESET_FILE}"

# ── Auto-apply saved position preference ─────────────────────────────────────
# Vertical presets: restore saved side (left/right), defaulting to left.
# Horizontal presets: restore saved position, defaulting to top. If a vertical
# position is recorded but we're switching to a horizontal preset, reset to top.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SET_POS="${SCRIPT_DIR}/set_position.sh"

# Legacy fallback for older setups that keep helper scripts in ~/.config/waybar/scripts.
if [[ ! -x "${SET_POS}" ]]; then
  SET_POS="${WAYBAR_DIR}/scripts/set_position.sh"
fi

if [[ "$PRESET" == vertical_* ]]; then
  SAVED_SIDE="$(cat "${VERTICAL_SIDE_FILE}" 2>/dev/null || echo "left")"
  if [[ -x "${SET_POS}" ]]; then
    info "Applying vertical side: ${SAVED_SIDE}"
    "${SET_POS}" "${SAVED_SIDE}" 2>/dev/null || true
  fi
else
  SAVED_POS="$(cat "${CURRENT_POSITION_FILE}" 2>/dev/null || echo "top")"
  if [[ "${SAVED_POS}" =~ ^(left|right)$ ]]; then
    SAVED_POS="top"
  fi
  if [[ -x "${SET_POS}" ]]; then
    info "Applying position: ${SAVED_POS}"
    "${SET_POS}" "${SAVED_POS}" 2>/dev/null || true
  fi
fi

info "Preset '${PRESET}' is live."

# ── Restart waybar ────────────────────────────────────────────────────────────
# CSS may already have reloaded via reload_style_on_change, but the config
# (position, modules, bar width) requires a full restart to take effect.
# We do this here so the switch is self-contained; Cloud Center does not need
# to chain a separate launch_waybar.sh call.

info "Restarting waybar…"
pkill waybar 2>/dev/null || true
sleep 0.3

if command -v uwsm-app &>/dev/null; then
  uwsm-app -- waybar &
else
  waybar &
fi

info "Done."

# ── Manual usage ──────────────────────────────────────────────────────────────
# From a terminal:  switch_style.sh <preset>
# No extra restart step needed — it's handled above.
