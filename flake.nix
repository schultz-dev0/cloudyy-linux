{
  description = "Cloudyy personal NixOS configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    # Only for SignalRGB: its binary is built on Arch and needs a newer glibc/libstdc++ than 26.05 ships.
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, zen-browser, ... }:
  let
    # RGB control on the desktop. Its udev rules grant HID/USB/serial via uaccess; i2c-dev exposes RAM/board RGB.
    signalrgbModule = let
      signalrgb = (import nixpkgs-unstable { system = "x86_64-linux"; config.allowUnfree = true; })
        .callPackage ./nixos/pkgs/signalrgb.nix { };
    in {
      environment.systemPackages = [ signalrgb ];
      services.udev.packages = [ signalrgb ];
      hardware.i2c.enable = true;
    };
    zenModule =
        {
      # The Cloudyy live-theme bridge is Zen autoconfig; /opt is not writable on NixOS, so bake it into the wrapper.
      environment.systemPackages = [
        (let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          unwrapped = zen-browser.packages.x86_64-linux.zen-browser-unwrapped;
        in pkgs.wrapFirefox (unwrapped // { version = unwrapped.firefoxVersion; }) {
          # Mirrors the flake's own zen-browser.nix, plus the Cloudyy bridge.
          pname = "zen-browser";
          version = unwrapped.version;
          extraPrefsFiles = [ "${./install/assets/zen/cloudyy.cfg}" ]; # interpolated so it enters the store
          extraAutoConfig = ''pref("general.config.sandbox_enabled", false);'';
        })
      ];
    };
  in {
    nixosConfigurations.cloudyy-laptop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/hosts/laptop
        ./nixos/modules/desktop.nix
        ./nixos/modules/network.nix
        ./nixos/modules/apps.nix
        ./nixos/modules/dev.nix
        zenModule
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.schultz = { imports = [ ./nixos/home.nix ]; cloudyy.syncthing.fresh = true; };
            backupFileExtension = "backup";
          };
        }
      ];
    };
    nixosConfigurations.cloudyy-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/hosts/desktop
        ./nixos/modules/desktop.nix
        ./nixos/modules/network.nix
        ./nixos/modules/apps.nix
        ./nixos/modules/dev.nix
        zenModule
        signalrgbModule
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # The desktop keeps its existing Syncthing identity (state lives in the shared /home).
            users.schultz = { imports = [ ./nixos/home.nix ]; cloudyy.syncthing.enable = true; };
            backupFileExtension = "backup";
          };
        }
      ];
    };
    nixosConfigurations.nixos-btw = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./nixos/hosts/vm
        ./nixos/modules/desktop.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.schultz = import ./nixos/home.nix;
            backupFileExtension = "backup";
          };
        }
      ];
    };
  };
}
