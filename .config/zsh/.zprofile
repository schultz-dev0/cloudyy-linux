if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec start-hyprland
fi



# Created by `pipx` on 2026-02-18 23:28:17
export PATH="$PATH:$HOME/.local/bin"
