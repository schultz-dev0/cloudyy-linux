#!/usr/bin/env bash
# ==============================================================================
# SSH AUTH MANAGER
# Ensures a single ssh-agent is running at a fixed socket path.
#
# Usage:
#   source ~/cloudyy_scripts/ssh-auth.sh   — sets SSH_AUTH_SOCK in current shell
#   ~/cloudyy_scripts/ssh-auth.sh          — starts agent (env won't propagate)
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

_load_keys_silently() {
    # 1. Wait for hyprlock to start (if it hasn't yet)
    local timeout=10
    while ! pgrep -x hyprlock >/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 0.5
        ((timeout--))
    done

    # 2. Wait for hyprlock to exit (meaning user has unlocked)
    while pgrep -x hyprlock >/dev/null; do
        sleep 0.5
    done

    # 3. Give PAM / gnome-keyring a moment to fully unlock the login keyring
    sleep 1.5

    # 4. Silent unlock attempt via GUI askpass helpers connected to gnome-keyring
    local askpass_helper=""
    for helper in "/usr/lib/seahorse/ssh-askpass" "/usr/lib/gcr4-ssh-askpass" "/usr/lib/gcr-ssh-askpass"; do
        if [[ -x "$helper" ]]; then
            askpass_helper="$helper"
            break
        fi
    done

    if [[ -n "$askpass_helper" ]]; then
        SSH_AUTH_SOCK="$AGENT_SOCK" SSH_ASKPASS="$askpass_helper" ssh-add ~/.ssh/id_ed25519 < /dev/null &>/dev/null || true
    fi
}

# If executed directly (not sourced), spawn the silent background unlocker
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        _load_keys_silently &
    fi
fi

key_count=$(SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l 2>/dev/null | grep -c 'SHA256' || true)
if [[ "${key_count:-0}" -eq 0 ]]; then
    echo "[ssh-auth] agent ready — no keys loaded. Run: ssh-add ~/.ssh/id_ed25519" >&2
else
    echo "[ssh-auth] agent ready — ${key_count} key(s) loaded" >&2
fi
