ZSH_DISABLE_COMPFIX=true

export ZSH="$HOME/.config/zsh/oh-my-zsh"
export ZSH_COMPDUMP="$HOME/.config/zsh/.zcompdump"
HISTFILE="$HOME/.config/zsh/.zsh_history"

DISABLE_AUTO_UPDATE=true

# ── Dynamic Plugins (Cloud Center) ───────────────────────────────────────────
plugins=(git)
if [[ -f ~/.config/cloud-center/settings/terminal/active_zsh_plugins.txt ]]; then
    while IFS= read -r plugin; do
        # Ignore empty lines and comments
        [[ -n "$plugin" && ! "$plugin" =~ ^# ]] && plugins+=("$plugin")
    done < ~/.config/cloud-center/settings/terminal/active_zsh_plugins.txt
fi

source $ZSH/oh-my-zsh.sh

export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"
STARSHIP_CACHE="$HOME/.cache/starship_init.zsh"
if [[ ! -f "$STARSHIP_CACHE" ]]; then
  starship init zsh > "$STARSHIP_CACHE"
fi
source "$STARSHIP_CACHE"


# Path management

typeset -U path
path=("$HOME/.local/bin" $path)

# personlisation

export EDITOR="nvim"

# SSH agent socket — systemd's ssh-agent.socket (enabled, socket-activated),
# needed because ssh-add reads this env var directly, unlike ssh/git which
# also honor ~/.ssh/config's IdentityAgent.
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"

# XDG user dirs
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]]; then
    set -a
    source "${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    set +a
fi

# aliases #

# general utility #
#
alias i='yay -S'
alias ir='yay -Rs'
alias iu='yay -Syu'
alias ic='sudo pacman -S'
alias icu='sudo pacman -Syu'
alias zshconfig='nvim ~/.config/zsh/.zshrc'
alias gparted='sudo -E gparted'

# Utility

alias ll='yazi'
alias oc='opencode'
alias cc='claude'
alias zj='zellij'

# power utility

alias sleep='systemctl suspend'
alias poweroff='sudo shutdown now'
alias reboot='sudo shutdown -r now'

# --- Top Left Startup Logo ---
SHOW_PIC=$(cat ~/.config/cloud-center/settings/terminal/show_mascot 2>/dev/null | tr '[:upper:]' '[:lower:]')
if [[ "$TERM" == "xterm-kitty" && -z "$INTELLISENSE" && "$SHOW_PIC" == "true" ]]; then
    MASCOT="$HOME/cloudyy-linux/extras/terminal_pic/hyprchan-lol.png"
    if [[ -f "$MASCOT" ]]; then
        IMG_H=$((LINES / 3))
        printf '\n%.0s' {1..$IMG_H}
        printf "\033[${IMG_H}A\033[0G"
        kitty +kitten icat \
            --place "${IMG_H}x${IMG_H}@0x0" \
            --scale-up \
            --transfer-mode file \
            --silent \
            "$MASCOT" 2>/dev/null
        printf "\033[${IMG_H}B\033[0G"
    fi
fi

# ── Multiplexer Autostart (Cloud Center) ────────────────────────────────────
cloudyy-terminal-multiplexer-autostart 2>/dev/null

if [ -z "$TMUX" ] && uwsm check may-start && uwsm select; then
    exec uwsm start default
fi

# Apply terminal settings from Cloud Center
cloudyy-terminal-kitty-sync 2>/dev/null
