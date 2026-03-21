# Path to your Oh My Zsh installation.
export ZSH="$HOME/.config/zsh/oh-my-zsh"
HISTFILE="$HOME/.config/zsh/.zsh_history"

plugins=(
  git
  zsh-autosuggestions
)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'


export ZSH_COMPDUMP="$ZDOTDIR/.zcompdump"

source $ZSH/oh-my-zsh.sh

# personlisation

eval "$(starship init zsh)"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh
export EDITOR="nvim"

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/cloudyy_scripts/cloudyy-other/:$PATH"


# aliases #

# general utility #
#
alias i='yay -S'
alias ir='yay -Rs'
alias ic='sudo pacman -S'
alias ping='ping -c'
alias iu='sudo pacman -Syu'
alias zshconfig='nvim ~/.config/zsh/.zshrc'
alias hyprconfig='nvim ~/dots/.config/hypr/hyprland.conf'
alias hyprbinds='nvim ~/dots/.config/hypr/source/bindings.conf'
alias windows='~/cloudyy_scripts/offtowindows.sh'
alias gparted='sudo -E gparted'
alias cloudyy_update="~/cloudyy_scripts/cloudyy-updater.sh"



# browser tabs #

alias canvas='xdg-open https://herts.instructure.com/'
alias studynet='xdg-open https://studynet.herts.ac.uk/studynet'
alias youtube='xdg-open https://www.youtube.com/'
alias gemini='xdg-open https://gemini.google.com/app'
alias swayncrestart='swaync-client -rs'
alias cloudyysync='cd ~/dots/ && git add . && vared -p "Commit message: " -c msg && git commit -m "$msg" && git push'
alias Samsungsync='cd ~/cloudyyOS/ && git add . && vared -p "Commit message: " -c msg && git commit -m "$msg" && git push'

# personl
alias remotedesk='~/cloudyy_scripts/ivanti/uni-rdp.sh'

# power utility

alias sleep='systemctl suspend'
alias poweroff='systemctl poweroff'



# --- Top Left Startup Logo ---
if [[ "$TERM" == "xterm-kitty" ]]; then
    IMG_H=$((LINES / 3))
    IMG_W=$((IMG_H / 1))

    printf '\n%.0s' $(seq 1 $IMG_H)
    printf "\033[${IMG_H}A\033[0G"
    kitty +kitten icat \
        --place "${IMG_W}x${IMG_H}@0x0" \
        --scale-up \
        --transfer-mode file \
        --silent \
        ~/extras/hyprchan-lol.png 2>/dev/null
    printf "\033[${IMG_H}B\033[0G"
fi

if uwsm check may-start && uwsm select; then
    exec uwsm start default
fi





