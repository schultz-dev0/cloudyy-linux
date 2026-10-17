# Port of the Arch ~/.config/zsh/.zshrc. Personal aliases (hosts, paths) stay out of
# the repo in ~/.config/zsh/personal.zsh, sourced below if present.
{ config, lib, pkgs, ... }:

let
  # Cloud Center's plugin browser scans ~/.config/zsh/oh-my-zsh/{plugins,custom/plugins},
  # so give it a real oh-my-zsh tree with the external plugins in custom/.
  omz = pkgs.runCommand "oh-my-zsh-cloudyy" { } ''
    mkdir -p $out
    cp -rs ${pkgs.oh-my-zsh}/share/oh-my-zsh/. $out/
    chmod -R u+w $out
    mkdir -p $out/custom/plugins/zsh-autosuggestions $out/custom/plugins/zsh-syntax-highlighting
    ln -s ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh \
      $out/custom/plugins/zsh-autosuggestions/
    echo 'source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
      > $out/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh
  '';
in
{
  programs.zsh = {
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = false; # oh-my-zsh runs compinit
    history.path = "${config.xdg.configHome}/zsh/.zsh_history";
    shellAliases = {
      ll = "yazi";
      oc = "opencode";
      cc = "claude";
      zj = "zellij";
      tm = "tmux";
      la = "ls -a -l";
      lg = "lazygit";
      sleep = "systemctl suspend";
      poweroff = "sudo shutdown now";
      reboot = "sudo shutdown -r now";
      seeya = "hyprctl dispatch exit";
      zshconfig = "nvim ~/cloudyy-linux/nixos/home/zsh.nix";
      rebuild = "sudo nixos-rebuild switch --flake path:$(jq -r .repo /etc/cloudyy/nixos.json)#$(jq -r .configuration /etc/cloudyy/nixos.json)";
    };
    initContent = ''
      ZSH_DISABLE_COMPFIX=true
      export ZSH="$HOME/.config/zsh/oh-my-zsh"
      export ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
      export ZSH_COMPDUMP="$HOME/.config/zsh/.zcompdump"
      mkdir -p "$ZSH_CACHE_DIR/completions"
      fpath+=("$ZSH_CACHE_DIR/completions")
      for profile in ''${(z)NIX_PROFILES}; do
        fpath+=($profile/share/zsh/site-functions $profile/share/zsh/vendor-completions)
      done
      DISABLE_AUTO_UPDATE=true

      # Dynamic plugins (Cloud Center)
      plugins=(git)
      if [[ -f ~/.config/cloud-center/settings/terminal/active_zsh_plugins.txt ]]; then
        while IFS= read -r plugin; do
          [[ -n "$plugin" && ! "$plugin" =~ ^# ]] && plugins+=("$plugin")
        done < ~/.config/cloud-center/settings/terminal/active_zsh_plugins.txt
      fi
      source $ZSH/oh-my-zsh.sh

      typeset -U path
      path=("$HOME/.local/bin" $path)

      if [[ -f "''${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs" ]]; then
        set -a; source "''${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"; set +a
      fi

      [[ -f ~/.config/zsh/personal.zsh ]] && source ~/.config/zsh/personal.zsh

      cloudyy-terminal-multiplexer-autostart 2>/dev/null
      cloudyy-terminal-kitty-sync 2>/dev/null
    '';
  };

  home.sessionVariables.EDITOR = "nvim";
  home.file.".config/zsh/oh-my-zsh".source = omz;
}
