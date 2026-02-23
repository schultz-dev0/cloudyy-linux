#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# switch_style.sh — Waybar preset switcher
# Copies a full preset (config.jsonc + style.css) from
#   ~/.config/waybar/presets/<name>/
# into the active location and restarts Waybar via launch_waybar.sh.
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

# ── Helpers ──────────────────────────────────────────────────────────────────

die()  { printf '[switch_style] ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[switch_style] %s\n' "$*" >&2; }

list_presets() {
  info "Available presets:"
  for d in "${PRESETS_DIR}"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    current=""
    [[ -f "${CURRENT_PRESET_FILE}" ]] && [[ "$(cat "${CURRENT_PRESET_FILE}")" == "$name" ]] \
      && current=" (active)"
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

[[ -d "${PRESET_DIR}" ]]              || die "Preset '${PRESET}' not found at ${PRESET_DIR}"
[[ -f "${PRESET_DIR}/config.jsonc" ]] || die "Preset '${PRESET}' missing config.jsonc"
[[ -f "${PRESET_DIR}/style.css" ]]    || die "Preset '${PRESET}' missing style.css"

# ── Atomic copy via temp files ────────────────────────────────────────────────
# Write to sibling temp files then rename — avoids Waybar reading a half-written file.

info "Switching to preset: ${PRESET}"

TMP_CONFIG="$(mktemp "${WAYBAR_DIR}/.config.XXXXXX.jsonc")"
TMP_STYLE="$(mktemp "${WAYBAR_DIR}/.style.XXXXXX.css")"

cleanup() { rm -f "${TMP_CONFIG}" "${TMP_STYLE}"; }
trap cleanup EXIT

cp "${PRESET_DIR}/config.jsonc" "${TMP_CONFIG}"
cp "${PRESET_DIR}/style.css"    "${TMP_STYLE}"

mv "${TMP_CONFIG}" "${ACTIVE_CONFIG}"
mv "${TMP_STYLE}"  "${ACTIVE_STYLE}"

# Record active preset for --list display and Cloud Center state restore
echo "${PRESET}" > "${CURRENT_PRESET_FILE}"

info "Config and style deployed. Preset '${PRESET}' is ready."

# ── Done ──────────────────────────────────────────────────────────────────────
# Waybar restart is intentionally NOT done here.
# Cloud Center chains the restart via launch_waybar.sh after this script exits,
# which avoids exec/trap races when called from GLib.spawn_async.
# To switch manually from a terminal:
#   switch_style.sh <preset> && ~/cloudyy_scripts/launch_waybar.sh
