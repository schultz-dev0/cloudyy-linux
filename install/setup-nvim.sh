#!/usr/bin/env bash
# setup-nvim.sh — Bootstrap lazy.nvim and install all plugins headlessly.
# Clones lazy.nvim explicitly rather than relying on nvim's in-config bootstrap,
# which doesn't behave reliably in headless mode.

set -euo pipefail -E

# --- Colors ------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

_ts() { date '+%H:%M:%S'; }
log()       { printf '%s[*]%s  [%s] %s\n' "$BLUE"   "$RESET" "$(_ts)" "$1"; }
log_ok()    { printf '%s[✓]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn()  { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error() { printf '%s[✗]%s  [%s] %s\n' "$RED"    "$RESET" "$(_ts)" "$1" >&2; }

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
}
trap '_err_handler' ERR

if ! command -v nvim &>/dev/null; then
  log_warn "nvim not found — skipping plugin bootstrap."
  exit 0
fi

# ── Clone lazy.nvim ───────────────────────────────────────────────────────────
LAZY_PATH="${HOME}/.local/share/nvim/lazy/lazy.nvim"

# Check for the actual entry point, not just the directory — a failed/partial
# clone leaves an empty dir which fools nvim's own fs_stat bootstrap check.
if [[ ! -f "${LAZY_PATH}/lua/lazy/init.lua" ]]; then
  log "Cloning lazy.nvim..."
  rm -rf "$LAZY_PATH"
  git clone --filter=blob:none --branch=stable \
    https://github.com/folke/lazy.nvim.git "$LAZY_PATH"
  log_ok "lazy.nvim cloned."
else
  log_ok "lazy.nvim already present."
fi

# ── tree-sitter CLI ───────────────────────────────────────────────────────────
# Install from pacman so Mason doesn't try to build it and get interrupted.
if ! command -v tree-sitter &>/dev/null; then
  log "Installing tree-sitter CLI..."
  sudo pacman -S --needed --noconfirm tree-sitter 2>/dev/null \
    || log_warn "tree-sitter pacman install failed — Mason will retry on first nvim open."
fi

# ── Sync plugins ──────────────────────────────────────────────────────────────
log "Syncing plugins (this may take a minute)..."

if timeout 300 nvim --headless \
    -c "lua require('lazy').sync({wait=true})" \
    -c "qa!"; then
  log_ok "Neovim plugins installed."
else
  log_warn "Plugin sync exited non-zero — open nvim to check, or run: nvim --headless -c \"lua require('lazy').sync({wait=true})\" -c 'qa!'"
fi
