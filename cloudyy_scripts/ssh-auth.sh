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

key_count=$(SSH_AUTH_SOCK="$AGENT_SOCK" ssh-add -l 2>/dev/null | grep -c 'SHA256' || true)
if [[ "${key_count:-0}" -eq 0 ]]; then
    echo "[ssh-auth] agent ready — no keys loaded. Run: ssh-add ~/.ssh/id_ed25519" >&2
else
    echo "[ssh-auth] agent ready — ${key_count} key(s) loaded" >&2
fi
