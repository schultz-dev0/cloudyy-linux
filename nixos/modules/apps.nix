# Everyday desktop apps (the Arch explicit-install list, minus drivers and AUR-only extras).
{ pkgs, ... }:
{
  programs.steam.enable = true;
  hardware.graphics.enable32Bit = true; # Steam's 32-bit runtime and Proton
  nixpkgs.config.allowUnfree = true; # obsidian, discord, claude-code, cursor

  environment.systemPackages = with pkgs; [
    obsidian discord telegram-desktop
    (callPackage ../pkgs/spotifast.nix { })
    chromium libreoffice-fresh
    obs-studio loupe
    keepassxc localsend proton-pass
    gnome-calculator file-roller gnome-disk-utility baobab gparted
    # agent tooling (configs are cloned from the desktop; log in once per tool)
    claude-code codex opencode code-cursor antigravity
  ];
}
