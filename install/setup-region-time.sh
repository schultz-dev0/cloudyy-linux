#!/usr/bin/env bash
# Install offline GeoNames data + GeoClue allowlist for Cloud Center.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BUILD_SCRIPT="${REPO_DIR}/cloudyy_scripts/cloud-center-v2/scripts/build_geonames_data.py"
readonly DATA_GZ="${REPO_DIR}/cloudyy_scripts/cloud-center-v2/data/geonames_cities1000.tsv.gz"
readonly CACHE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/cloud-center"
readonly CACHE_GZ="${CACHE_DIR}/geonames_cities1000.tsv.gz"
readonly GEOCLUE_DROPIN="/etc/geoclue/conf.d/50-cloudyy-allow-cloud-center.conf"

log() { printf '[*] %s\n' "$*"; }

install_geonames_data() {
  if [[ ! -f "$BUILD_SCRIPT" ]]; then
    log "GeoNames build script missing — skip"
    return 0
  fi

  if [[ ! -f "$DATA_GZ" ]]; then
    log "Building offline place-name database (one-time download)…"
    python3 "$BUILD_SCRIPT"
  fi

  if [[ -f "$DATA_GZ" ]]; then
    mkdir -p "$CACHE_DIR"
    cp -f "$DATA_GZ" "$CACHE_GZ"
    log "Installed geonames data → $CACHE_GZ"
  fi
}

install_geoclue_allow() {
  local user="${USER:-}"
  [[ -n "$user" ]] || return 0

  if [[ -f "$GEOCLUE_DROPIN" ]] && grep -q "cloud-center" "$GEOCLUE_DROPIN" 2>/dev/null; then
    log "GeoClue allow drop-in already present"
    return 0
  fi

  log "Installing GeoClue allow drop-in for Cloud Center…"
  sudo mkdir -p /etc/geoclue/conf.d
  sudo tee "$GEOCLUE_DROPIN" >/dev/null <<EOF
[cloud-center]
allowed=true
system=false
users=${user}
EOF
  sudo systemctl restart geoclue.service 2>/dev/null || true
  log "GeoClue configured for user ${user}"
}

main() {
  install_geonames_data
  install_geoclue_allow
}

main "$@"
