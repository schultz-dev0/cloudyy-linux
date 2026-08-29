#!/usr/bin/env bash
# setup-nvim.sh — Bootstrap the NvChad-based config headlessly.
# NvChad 2.5 is loaded as a plugin by ~/.config/nvim (NvChad/starter layout);
# its init.lua self-bootstraps lazy.nvim. This script drives the first plugin
# sync + base46 theme compile so the first interactive launch is clean.

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

# ── tree-sitter CLI ───────────────────────────────────────────────────────────
# Install from pacman so Mason doesn't try to build it and get interrupted.
if ! command -v tree-sitter &>/dev/null; then
  log "Installing tree-sitter CLI..."
  sudo pacman -S --needed --noconfirm tree-sitter 2>/dev/null \
    || log_warn "tree-sitter pacman install failed — Mason will retry on first nvim open."
fi

# ── Sync plugins ──────────────────────────────────────────────────────────────
# NvChad's init.lua clones lazy.nvim itself if missing, so `lazy.sync` here is
# enough to pull NvChad + base46 + the rest.
log "Syncing plugins (this may take a minute)..."
if timeout 300 nvim --headless \
    -c "lua require('lazy').sync({wait=true})" \
    -c "qa!"; then
  log_ok "Neovim plugins installed."
else
  log_warn "Plugin sync exited non-zero — open nvim to check, or run: nvim --headless -c \"lua require('lazy').sync({wait=true})\" -c 'qa!'"
fi

# ── Compile base46 theme cache ────────────────────────────────────────────────
# init.lua does `dofile(base46_cache .. "defaults")` on every launch; that file
# only exists once base46 has compiled. Build it now so the first interactive
# launch doesn't error before NvChad gets a chance to compile it lazily.
log "Compiling base46 theme cache..."
if timeout 60 nvim --headless \
    -c "lua pcall(function() require('base46').load_all() end)" \
    -c "qa!"; then
  log_ok "base46 cache compiled."
else
  log_warn "base46 compile exited non-zero — first nvim launch will compile it instead."
fi
