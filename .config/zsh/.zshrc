# DISABLE Instant Prompt to allow startup graphics
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.config/zsh/oh-my-zsh"
HISTFILE="$HOME/.config/zsh/.zsh_history"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  zsh-autosuggestions
)

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'


export ZSH_COMPDUMP="$ZDOTDIR/.zcompdump"

source $ZSH/oh-my-zsh.sh
#source ~/.cargo/env

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"

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
