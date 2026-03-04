typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


# Path to your Oh My Zsh installation.
export ZSH="$HOME/.config/zsh/oh-my-zsh"
HISTFILE="$HOME/.config/zsh/.zsh_history"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  zsh-autosuggestions
)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'


export ZSH_COMPDUMP="$ZDOTDIR/.zcompdump"

source $ZSH/oh-my-zsh.sh

# personlisation

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f $ZDOTDIR/.p10k.zsh ]] || source $ZDOTDIR/.p10k.zsh
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



# --- Top Left Startup Logo ---
if [[ "$TERM" == "xterm-kitty" ]]; then
    # Configure size here (in terminal text cells)
    # You may need to tweak IMG_W to fix the aspect ratio (squished/stretched)
    IMG_H=18 
    IMG_W=30 

    # 1. Display Image at Top-Left (0x0)
    # The image is drawn as an overlay, so it doesn't move text by itself.
    kitty +kitten icat --place "${IMG_W}x${IMG_H}@0x0" ~/extras/hyprchan-lol.png

    # 2. Push the prompt down
    # We print empty lines equal to the image height so the prompt appears below it.
    for ((i=0; i<IMG_H; i++)); do echo; done
fi

if uwsm check may-start && uwsm select; then
    exec uwsm start default
fi

# pnpm
export PNPM_HOME="/home/schultz/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Created by `pipx` on 2026-02-18 23:28:17
export PATH="$HOME/cloudyy_scripts:$HOME/cloudyy_scripts/cloudyy-other:$HOME/.local/bin:$PATH"

. "$HOME/.local/bin/env"


