#!/usr/bin/env bash
# ==============================================================================
# SSH AUTH MANAGER
# Ensures a single ssh-agent is running at a fixed socket path.
#
# Usage:
#   source ~/cloudyy_scripts/ssh-auth.sh   — sets SSH_AUTH_SOCK in current shell
#   ~/cloudyy_scripts/ssh-auth.sh          — starts agent (env won't propagate)
#   ~/cloudyy_scripts/ssh-auth.sh --setup  — one-time passphrase setup
#
# The socket path is fixed at ~/.ssh/ssh-agent.socket.
# ~/.ssh/config has IdentityAgent pointing here so SSH tools (git, ssh)
# find the agent automatically without SSH_AUTH_SOCK being set.
# ==============================================================================

readonly AGENT_SOCK="${HOME}/.ssh/ssh-agent.socket"

_agent_responsive() {
  SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l >/dev/null 2>&1
  # rc=0: alive + has keys  rc=1: alive + no keys  rc=2: unreachable
  [[ $? -ne 2 ]]
}

_start_agent() {
  rm -f "$AGENT_SOCK"
  ssh-agent -a "$AGENT_SOCK" >/dev/null 2>&1
}

if [[ -S "$AGENT_SOCK" ]]; then
  if ! _agent_responsive; then
    echo "[ssh-auth] stale socket — restarting agent" >&2
    _start_agent
  fi
else
  echo "[ssh-auth] starting agent" >&2
  _start_agent
fi

export SSH_AUTH_SOCK="$AGENT_SOCK"

# ---------------------------------------------------------------------------
# One-time setup: change SSH key passphrase to match login password and save
# it in gnome-keyring so future logins load the key automatically.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--setup" ]]; then
  echo "======================================================================"
  echo "SSH PASSPHRASE SETUP — run once"
  echo "======================================================================"
  echo "Your SSH key passphrase must match your login / hyprlock password."
  echo ""
  echo "Step 1: Changing SSH key passphrase..."
  ssh-keygen -p -f "${HOME}/.ssh/id_ed25519"
  echo ""
  echo "Step 2: Saving passphrase to gnome-keyring for auto-loading..."
  read -rsp "Re-enter the new passphrase: " _setup_pass
  echo
  if printf '%s' "$_setup_pass" | secret-tool store \
    --label="SSH Key id_ed25519" ssh-passphrase id_ed25519 2>/dev/null; then
    echo "Passphrase saved to keyring."
  else
    echo "ERROR: Could not save to keyring. Is gnome-keyring-daemon running?" >&2
    exit 1
  fi
  echo ""
  echo "Step 3: Loading key into agent now..."
  SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add "${HOME}/.ssh/id_ed25519"
  echo ""
  echo "Done. On every reboot, your SSH key will load automatically when"
  echo "you enter your password (via hyprlock or the keyring unlock prompt)."
  exit 0
fi

# ---------------------------------------------------------------------------
# Load the SSH key using the passphrase stored in gnome-keyring.
# Called at startup; also falls back to waiting for hyprlock to unlock.
# ---------------------------------------------------------------------------
_load_key_from_keyring() {
  local passphrase tmp b64
  passphrase=$(secret-tool lookup ssh-passphrase id_ed25519 2>/dev/null)
  [[ -n "$passphrase" ]] || return 1

  tmp=$(mktemp /tmp/.askpass.XXXXXX) || return 1
  chmod 700 "$tmp"
  b64=$(printf '%s' "$passphrase" | base64 -w0)
  # Embed passphrase as base64 in a throwaway askpass script to avoid quoting issues.
  printf '#!/bin/bash\nprintf "%%%%s" "$(base64 -d <<< %s)"\n' "$b64" >"$tmp"

  SSH_AUTH_SOCK="$AGENT_SOCK" SSH_ASKPASS="$tmp" SSH_ASKPASS_REQUIRE=force \
    ssh-add ~/.ssh/id_ed25519 </dev/null 2>/dev/null
  local rc=$?
  rm -f "$tmp"
  return $rc
}

_load_keys_silently() {
  sleep 2 # let the Wayland session settle

  # First attempt — gnome-keyring will show an unlock prompt if still locked
  # (happens on autologin fresh boot; same password as hyprlock).
  _load_key_from_keyring && return 0

  # Fallback: wait for hyprlock to appear and then exit (PAM unlocks keyring).
  local timeout=60
  while ! pgrep -x hyprlock >/dev/null && [[ $timeout -gt 0 ]]; do
    sleep 0.5
    ((timeout--))
  done
  while pgrep -x hyprlock >/dev/null; do
    sleep 0.5
  done
  sleep 1

  _load_key_from_keyring
}

# Spawn background key loader when executed directly (not sourced).
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
  if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
    _load_keys_silently &
  fi
fi

key_count=$(SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l 2>/dev/null | grep -c 'SHA256' || true)
if [[ "${key_count:-0}" -eq 0 ]]; then
  # Only prompt for setup if no passphrase is stored — means --setup was never run.
  # If passphrase IS stored, keys are loading in the background; stay silent.
  if ! secret-tool lookup ssh-passphrase id_ed25519 >/dev/null 2>&1; then
    echo "[ssh-auth] agent ready — no keys loaded. Run: ~/cloudyy_scripts/ssh-auth.sh --setup" >&2
  fi
fi
