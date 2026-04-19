#!/usr/bin/env bash
# ==============================================================================
# SSH AUTH MANAGER
# Ensures a single ssh-agent is running with a fixed socket path.
# ==============================================================================

readonly SSH_DIR="${HOME}/.ssh"
readonly SSH_AGENT_SOCK="${SSH_DIR}/ssh-agent.socket"

setup_agent() {
    # If the socket exists but the process is gone, cleanup
    if [[ -S "$SSH_AGENT_SOCK" ]]; then
        export SSH_AUTH_SOCK="$SSH_AGENT_SOCK"
        if ! ssh-add -l >/dev/null 2>&1; then
            if [[ $? -eq 2 ]]; then
                # Agent unreachable, remove stale socket
                rm -f "$SSH_AGENT_SOCK"
            fi
        fi
    fi

    # Start agent if socket is missing
    if [[ ! -S "$SSH_AGENT_SOCK" ]]; then
        ssh-agent -a "$SSH_AGENT_SOCK" > /dev/null
    fi

    export SSH_AUTH_SOCK="$SSH_AGENT_SOCK"
}

setup_agent

# Export for sub-shells if sourced
export SSH_AUTH_SOCK
