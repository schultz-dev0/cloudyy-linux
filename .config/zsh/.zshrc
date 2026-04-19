ZSH_DISABLE_COMPFIX=true

export ZSH="$HOME/.config/zsh/oh-my-zsh"
export ZSH_COMPDUMP="$HOME/.config/zsh/.zcompdump"
HISTFILE="$HOME/.config/zsh/.zsh_history"

DISABLE_AUTO_UPDATE=true

plugins=(
  git
  zsh-autosuggestions
)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#888888'

source $ZSH/oh-my-zsh.sh

STARSHIP_CACHE="$HOME/.cache/starship_init.zsh"
if [[ ! -f "$STARSHIP_CACHE" ]]; then
  starship init zsh > "$STARSHIP_CACHE"
fi
source "$STARSHIP_CACHE"

# Path management

typeset -U path
path=("$HOME/.local/bin" "$HOME/cloudyy_scripts/cloudyy-other/" "$HOME/cloudyy_scripts/" $path)

# personlisation

export EDITOR="nvim"

# aliases #

# general utility #
#
alias i='yay -S'
alias ir='yay -Rs'
alias ic='sudo pacman -S'
alias ping='ping -c'
alias iu='sudo pacman -Syu'
alias zshconfig='nvim ~/.config/zsh/.zshrc'
alias gparted='sudo -E gparted'
alias cloudyy_update="~/cloudyy_scripts/cloudyy-updater.sh"
alias systemscommit='cd ~/Uni_stuff/control_systems/ && git add . && vared -p "Commit message: " -c msg && git commit -m "$msg" && git push'

# browser tabs #

alias canvas='xdg-open https://herts.instructure.com/'
alias studynet='xdg-open https://studynet.herts.ac.uk/studynet'
alias youtube='xdg-open https://www.youtube.com/'
alias swayncrestart='swaync-client -rs'
alias cloudyysync='cd ~/cloudyy-linux/ && git add . && vared -p "Commit message: " -c msg && git commit -m "$msg" && git push'
alias Samsungsync='cd ~/cloudyyOS/ && git add . && vared -p "Commit message: " -c msg && git commit -m "$msg" && git push'

# personl
alias remotedesk='~/cloudyy_scripts/ivanti/uni-rdp.sh'

# power utility

alias sleep='systemctl suspend'
alias poweroff='sudo shutdown now'
alias reboot='sudo shutdown -r now'
alias seeya='hyprctl dispatch exit'


# --- Top Left Startup Logo ---
if [[ "$TERM" == "xterm-kitty" && -z "$INTELLISENSE" ]]; then
    IMG_H=$((LINES / 3))
    # Removed the 'seq' call and used zsh brace expansion for speed
    printf '\n%.0s' {1..$IMG_H}
    printf "\033[${IMG_H}A\033[0G"
    kitty +kitten icat \
        --place "${IMG_H}x${IMG_H}@0x0" \
        --scale-up \
        --transfer-mode file \
        --silent \
        ~/extras/hyprchan-lol.png 2>/dev/null
    printf "\033[${IMG_H}B\033[0G"
fi

if uwsm check may-start && uwsm select; then
    exec uwsm start default
fi





# opencode
export PATH=/home/schultz/.opencode/bin:$PATH
