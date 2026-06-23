#!/usr/bin/env bash
# =============================================================================
# bin_check.sh — Cloudyy Binary Seeder
# =============================================================================
# Symlinks a curated list of shipped binaries from the repo into ~/.local/bin/
# (already on PATH on Arch), so users don't need a custom PATH entry pointing
# at cloudyy_scripts/cloudyy-other/.
#
# Usage:
#   bin_check.sh                    Same as `seed`
#   bin_check.sh seed   [repo_dir]  Symlink each known binary into ~/.local/bin/
#   bin_check.sh check  [repo_dir]  Print source/target/status for every known binary
#   bin_check.sh where  <name>      Print the resolved source path for one binary
#   bin_check.sh help               Show this message
#
# Called by install.sh (phase_bin_seed) on first install.
# =============================================================================

set -euo pipefail -E

# --- Constants ---------------------------------------------------------------
readonly DEFAULT_REPO_DIR="${HOME}/cloudyy-linux"
readonly BIN_TARGET_DIR="${HOME}/.local/bin"
readonly BACKUP_DIR="${HOME}/.config/cloudyy-backups/$(date +%Y%m%d_%H%M%S)/bin"

# Curated list of binary file names shipped under cloudyy_scripts/cloudyy-other/.
# AUR-managed binaries (hcm, cloudyy-system-monitor) are installed in the packages phase.
readonly -a BIN_NAMES=(
  # rusty_keys     # add when the binary lands in cloudyy-other/
)

# --- Colors (TTY-aware) ------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# --- Logging -----------------------------------------------------------------
_ts() { date '+%H:%M:%S'; }
log_ok() { printf '%s[✓]%s  [%s] %s\n' "$GREEN" "$RESET" "$(_ts)" "$1"; }
log_warn() { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_write() { printf '%s[+]%s  [%s] %s\n' "$GREEN" "$RESET" "$(_ts)" "$1"; }
log_skip() { printf '%s[-]%s  [%s] %s %s(unchanged)%s\n' "$CYAN" "$RESET" "$(_ts)" "$1" "$YELLOW" "$RESET"; }
log_error() { printf '%s[✗]%s  [%s] %s\n' "$RED" "$RESET" "$(_ts)" "$1" >&2; }

# --- Guards ------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
  log_error "Do not run as root."
  exit 1
fi

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  log_error "  in ${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}:${FUNCNAME[1]:-main}"
}
trap '_err_handler' ERR

# =============================================================================
# SUBCOMMANDS
# =============================================================================

usage() {
  cat <<'EOF'
Usage:
  bin_check.sh                    Same as `seed`
  bin_check.sh seed   [repo_dir]  Symlink each known binary into ~/.local/bin/
  bin_check.sh check  [repo_dir]  Print source/target/status for every known binary
  bin_check.sh where  <name>      Print the resolved source path for one binary
  bin_check.sh help               Show this message

[repo_dir] defaults to $HOME/cloudyy-linux.
EOF
}

# --- seed --------------------------------------------------------------------
cmd_seed() {
  local repo_dir="${1:-$DEFAULT_REPO_DIR}"
  local bin_source_dir="${repo_dir}/cloudyy_scripts/cloudyy-other"

  mkdir -p "$BIN_TARGET_DIR"

  if [[ ${#BIN_NAMES[@]} -eq 0 ]]; then
    log_skip "No repo-shipped binaries configured (AUR packages use packages phase)"
    return 0
  fi

  if [[ ! -d "$bin_source_dir" ]]; then
    log_error "Binary source directory not found: ${bin_source_dir}"
    return 1
  fi

  local seeded=0 unchanged=0 skipped=0 errors=0

  for name in "${BIN_NAMES[@]}"; do
    local src="${bin_source_dir}/${name}"
    local dst="${BIN_TARGET_DIR}/${name}"

    if [[ ! -f "$src" ]]; then
      log_warn "Source not found: ${name} (expected at ${src})"
      ((++skipped))
      continue
    fi

    if [[ ! -x "$src" ]]; then
      log_warn "Source not executable: ${name} (${src})"
      ((++skipped))
      continue
    fi

    if [[ -L "$dst" ]]; then
      # Existing symlink — keep if already correct, else replace.
      local current
      current="$(readlink "$dst" 2>/dev/null || true)"
      if [[ "$current" == "$src" ]]; then
        log_skip "$name"
        ((++unchanged))
        continue
      fi
      rm -f "$dst"
    elif [[ -e "$dst" ]]; then
      # Real file or directory in our way — back it up before replacing.
      mkdir -p "$BACKUP_DIR"
      mv "$dst" "${BACKUP_DIR}/${name}"
      log_warn "Backed up existing ${dst} → ${BACKUP_DIR}/${name}"
    fi

    if ln -snf "$src" "$dst"; then
      log_write "Seeded: ${name} → ${src}"
      ((++seeded))
    else
      log_error "Failed to symlink ${name}"
      ((++errors))
    fi
  done

  printf '\n%s%sSummary:%s seeded=%d  unchanged=%d  skipped=%d  errors=%d\n' \
    "$BOLD" "$CYAN" "$RESET" "$seeded" "$unchanged" "$skipped" "$errors"

  ((errors == 0))
}

# --- check -------------------------------------------------------------------
cmd_check() {
  local repo_dir="${1:-$DEFAULT_REPO_DIR}"
  local bin_source_dir="${repo_dir}/cloudyy_scripts/cloudyy-other"

  local rc=0

  for name in "${BIN_NAMES[@]}"; do
    local src="${bin_source_dir}/${name}"
    local dst="${BIN_TARGET_DIR}/${name}"
    local status

    if [[ -L "$dst" ]]; then
      local current
      current="$(readlink "$dst" 2>/dev/null || true)"
      if [[ ! -f "$src" ]]; then
        status="missing-source"
      elif [[ "$current" == "$src" ]]; then
        status="seeded"
      else
        status="stale"
        rc=1
      fi
    elif [[ -e "$dst" ]]; then
      status="conflict"
      rc=1
    elif [[ ! -f "$src" ]]; then
      status="missing-source"
    else
      status="missing-target"
    fi

    printf '%-30s source=%s | target=%s | status=%s\n' \
      "$name" "$src" "$dst" "$status"
  done

  return $rc
}

# --- where -------------------------------------------------------------------
cmd_where() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    log_error "Usage: bin_check.sh where <name>"
    return 2
  fi

  local found=0
  for known in "${BIN_NAMES[@]}"; do
    if [[ "$known" == "$name" ]]; then
      found=1
      break
    fi
  done

  if ((found == 0)); then
    log_error "Unknown binary: ${name} (not in BIN_NAMES)"
    return 1
  fi

  local src="${DEFAULT_REPO_DIR}/cloudyy_scripts/cloudyy-other/${name}"
  if [[ ! -f "$src" ]]; then
    log_error "Source missing: ${src}"
    return 1
  fi

  printf '%s\n' "$src"
}

# =============================================================================
# DISPATCH
# =============================================================================
main() {
  local cmd="${1:-seed}"
  shift || true

  # `|| rc=$?` short-circuits set -E so the ERR trap doesn't fire on
  # intentional non-zero returns (e.g. check finding stale links, where
  # being asked about an unknown binary).
  local rc=0
  case "$cmd" in
  seed) cmd_seed "$@" || rc=$? ;;
  check) cmd_check "$@" || rc=$? ;;
  where) cmd_where "$@" || rc=$? ;;
  help | --help | -h)
    usage
    exit 0
    ;;
  *)
    log_error "Unknown subcommand: ${cmd}"
    usage >&2
    exit 1
    ;;
  esac
  exit $rc
}

main "$@"
