{ config, lib, pkgs, ... }:

{
  imports = [ ./home/syncthing.nix ./home/desktop.nix ./home/zsh.nix ];

	home.username = "schultz";
	home.homeDirectory = "/home/schultz";
	programs.git.enable = true;
	programs.zsh = {
		enable = true;
		initContent = lib.mkBefore ''
			export STARSHIP_CONFIG="${config.home.sessionVariables.STARSHIP_CONFIG}"
		'';
	};
	programs.starship = {
		enable = true;
		enableBashIntegration = true;
		enableZshIntegration = true;
	};
	home.sessionVariables.STARSHIP_CONFIG = lib.mkForce "${config.xdg.stateHome}/cloudyy/current/theme/applications/starship.toml";
	home.stateVersion = "26.05";
	programs.bash = {
		enable = true;
		initExtra = ''
			export STARSHIP_CONFIG="${config.home.sessionVariables.STARSHIP_CONFIG}"
		'';
		shellAliases = {btw = "echo I use nixos btw";};
		# Arch autostarted Hyprland via uwsm on login; same idea with start-hyprland on tty1.
		# The tty login shell is bash. Escape hatch: touch ~/.no-hypr-autostart from another VT.
		profileExtra = ''
			if [[ -z "$WAYLAND_DISPLAY" && -z "$TMUX" && "$XDG_VTNR" == 1 && ! -e ~/.no-hypr-autostart ]]; then
				# Plymouth holds DRM master until released; Hyprland's backend fails to start otherwise (same as the Arch zshrc).
				command -v plymouth >/dev/null && plymouth deactivate 2>/dev/null || true
				exec start-hyprland
			fi
		'';
	};

}
