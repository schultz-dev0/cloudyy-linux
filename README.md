Disclaimer: Some of the things in this projects are written with AI, as this is a work in progress project I will overwrite and fix things as I go, but AI makes my student life easier. Thanks! Enjoy the dotfiles.

A Hyprland rice for Arch Linux — Material-You theming via matugen, dynamic light/dark switching, and a full interactive installer.

## Install

```bash
sudo pacman -S git
git clone https://github.com/schultz-dev0/cloudyy-linux ~/cloudyy-linux
~/cloudyy-linux/install/install.sh
```

Follow the prompts — the installer handles GPU detection, package selection, dotfiles symlinking, and service setup automatically. Resumes from the last checkpoint if interrupted.

## Usage

Most features are shown in this video: https://www.youtube.com/watch?v=rspzOLU1LwU

- **Theme toggle**: `~/cloudyy_scripts/theme_controller.sh toggle`
- **Rofi launcher**: `Super + Alt + Space` — includes app launcher, keybind help, theme picker, and more
- **Quickshell shell**: bar, notifications, and shell UI are provided by quickshell by default
- **Waybar presets**: legacy assets kept in-repo during the transition; not part of the active default shell path
- **Obsidian vault**: drop your vault in the blank obsidian vault (or any path) — matugen will colour-match it

## Waybar presets (legacy)
**You can change orientation top and bottom | left and right**
![Preview](extras/Previewpics/waybar/waybar_default.png)

![Preview](extras/Previewpics/waybar/waybar_ghost.png)

![Preview](extras/Previewpics/waybar/waybar_matrix.png)


## previews:
- **Cloud center**

![Preview](extras/Previewpics/general/cloud_center_home.png)

![Preview](extras/Previewpics/general/battery1.png)
                                                   
![Preview](extras/Previewpics/general/battery2.png)

- **Fast fetch**

![Preview](extras/Previewpics/general/fast_fetch.png)

- **Rofi**

![Preview](extras/Previewpics/general/rofi.png)

- **Swaync menu**

![Preview](extras/Previewpics/general/swaync.png)

- **Terminal with starship**

![Preview](extras/Previewpics/general/terminal.png)

- **Vscode/vscodium theming via matugen**

![Preview](extras/Previewpics/general/vscode_theming.png)
