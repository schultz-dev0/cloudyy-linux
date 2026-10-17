{ pkgs, ... }:
{
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = true;
  programs.thunar.enable = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  security.polkit.enable = true;
  programs.firefox.enable = true;
  programs.dconf.enable = true;
  programs.zsh.enable = true;
  # oh-my-zsh runs its own cached compinit; the global one fights it over the dump file.
  programs.zsh.enableGlobalCompInit = false;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.cloudyy-lock = {};
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono noto-fonts noto-fonts-color-emoji material-symbols
  ];
  # Cloudyy edits its settings and generated theme files at runtime.
  environment.systemPackages = with pkgs; [
    neovim wget git kitty
    quickshell jq ripgrep fd
    wl-clipboard cliphist libnotify
    brightnessctl pamixer playerctl pulseaudio
    grim slurp satty pavucontrol
    (callPackage ../pkgs/hyprcap.nix { })
    hypridle hyprsunset hyprpolkitagent
    awww matugen imagemagick ffmpeg tesseract
    inotify-tools socat procps psmisc util-linux rsync
    gsettings-desktop-schemas glib gtk3 gtk4 libadwaita
    papirus-icon-theme bibata-cursors adwaita-icon-theme
    curl unzip xdg-utils desktop-file-utils
    bluez networkmanager ddcutil lm_sensors
    btop cava yazi zellij fzf fastfetch
    lazygit github-cli git-lfs tealdeer ncdu nmap yt-dlp stow btrfs-progs man-db nano tmux bat eza tree zip
    xdotool vips openssl pciutils adw-gtk3 networkmanagerapplet
    wlogout hyprpicker wf-recorder swayosd yad mpv qt6Packages.qt6ct libsForQt5.qt5ct qt6Packages.qtstyleplugin-kvantum
    (python3.withPackages (ps: [ ps.pyyaml ps.pygobject3 ps.psutil ps.requests ps.pillow ]))
  ];
}
