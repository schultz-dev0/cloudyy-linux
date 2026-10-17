# Cloudyy on NixOS

Personal system configuration. The desktop port supplies NixOS/Home Manager,
Hyprland, the Cloudyy shell, Cloud Center dependencies, audio, keyring, lock PAM
service, and core tools. Arch package management and physical hardware workflows
still need separate ports.

Home Manager links the desktop to `~/cloudyy-linux`, seeds writable Hyprland
defaults once (backing up existing entry files), and bootstraps the mono theme.
Keep that checkout in place. Start the desktop with `start-hyprland` after login.

`cloudyy-laptop` targets the ASUS Vivobook S 14 at `192.168.0.248`. It uses the
laptop's existing Limine boot setup and LUKS-encrypted Btrfs subvolumes. Its
hardware module was copied from that machine; do not use it on other hardware.
The original configuration and system path are backed up on the laptop in
`~/cloudyy-port-backup/`.

Inside the laptop's clean source copy:

```sh
sudo nixos-rebuild switch --flake 'path:/home/schultz/cloudyy-linux#cloudyy-laptop'
```

After the first activation, log in again (or run `exec bash -l`) before starting
`start-hyprland`, so the session picks up the new profile environment. Unlock the
Cloudyy lockscreen with the existing user password.

Starship runs in both Bash and Zsh and reads the active theme's prompt profile.
The shell startup files set that path explicitly so newly opened terminals also
work in a desktop session that predates a rebuild. GTK settings schemas are
provided to the Cloudyy commands and shell service. Bluetooth is enabled on the
laptop; Thunar retains the existing Cloudyy styling.

`cloudyy-update --dry-run` previews the NixOS update commands. `cloudyy-update`
asks for confirmation, backs up `flake.lock`, updates the locked inputs, builds,
and then activates the new system with sudo. Logs and the previous lock file are
saved under `~/.local/state/cloudyy/updates/`. A failed build does not activate a
new generation; its updated lock file remains in the checkout for inspection.
The host-specific target is declared in `/etc/cloudyy/nixos.json`. The package
UI (Spotlight > Packages) lists the declared packages; "remove" opens the
declaration in `$EDITOR` and offers a rebuild, never an imperative uninstall.

`nixos-btw` targets the existing GNOME Boxes VM. Its disk UUIDs and boot settings
are VM-specific; do not activate this configuration on the Arch host or another
machine. The future physical-host configuration must have its own hardware module.

- `../flake.nix`: entry point and Home Manager integration.
- `../flake.lock`: exact inputs copied from the working VM.
- `hosts/vm/`: VM boot, disks, user, locale, and guest agent.
- `hosts/laptop/`: laptop hardware, encrypted disks, user, and locale.
- `modules/boot.nix`: shared UEFI Limine bootloader.
- `modules/desktop.nix`: shared desktop packages and services.
- `home.nix`: existing user configuration, preserved from the VM.

Once these files are tracked in your checkout, inside the VM:

```sh
sudo nixos-rebuild build --flake ~/cloudyy-linux#nixos-btw
sudo nixos-rebuild test --flake ~/cloudyy-linux#nixos-btw
# After checking the session, audio, and applications:
sudo nixos-rebuild switch --flake ~/cloudyy-linux#nixos-btw
```

New files must be tracked for a Git-backed flake to see them. No commit is needed
for local evaluation. Do not use `path:` on the entire live Cloudyy checkout: it
also contains ignored runtime files and sockets. A clean directory containing
the tracked desktop sources plus `flake.nix`, `flake.lock`, and `nixos/` can be
evaluated with `path:` instead. The VM currently uses such a clean source copy:

```sh
sudo nixos-rebuild switch --flake 'path:/home/schultz/cloudyy-linux#nixos-btw'
```

The configuration preserves mutable user passwords and both stateVersion values.
Cloudyy's generated themes and live desktop settings remain writable. No Arch
installer is invoked. `test` activates only the running session; `switch` also
updates the default boot generation.

## Storage target

The final machine will use Limine and Btrfs, retaining LUKS encryption from the
current Arch system. The existing VM remains ext4 until a separate Btrfs test
disk is provisioned. Editing `fsType` does not convert or format a filesystem.

Proposed Btrfs layout: `@` for `/`, `@home` for `/home`, `@nix` for `/nix`,
and `@log` for `/var/log`, with `compress=zstd:3`. Keep the EFI system partition
FAT32, mounted at `/boot`. Size it for multiple kernel/initrd generations.
Filesystem declarations must use the actual disk UUIDs and existing subvolumes.
No formatting or conversion is performed by this configuration.

Btrfs snapshots and NixOS generations serve different purposes. Snapshot/restore
policy is still to be defined; a root-only snapshot excluding `/nix` is not a
complete rollback of NixOS package state.

## Syncthing migration

The Home Manager option `cloudyy.syncthing.enable` defaults to false. Enable it
only on the replacement physical host after restoring the state and data; do not
run the VM and desktop concurrently with the same Syncthing identity.

Current user service: `syncthing.service`. State: `~/.local/state/syncthing/`.
Preserve the complete directory privately (config.xml, cert.pem, key.pem, HTTPS
keys and index-v2). These files must not be put into Git or the Nix store.
Stop the source service for the final consistent state copy. Restore ownership
and permissions and all folder contents, including .stfolder and any .stignore
files, before starting the replacement service. Retain an independent backup.

Current folders (all send/receive):

| ID | Folder |
| --- | --- |
| bjniv-fo5sh | /home/schultz/RUSTProjects |
| mlvpj-amnay | /home/schultz/openconnect_patch |
| sqsv4-hwn5u | /home/schultz/projects |

The first path is relative in config.xml; the service explicitly keeps its working
directory at /home/schultz. GUI stays as restored, currently 127.0.0.1:8384.
Folder versioning is not currently enabled. Sync is not an independent backup.
Verify the device ID, folder IDs, local data and peer status during cutover.
The service refuses startup until the restored configuration and identity exist.
Firewall rules for discovery/transfers belong in the eventual physical-host
module; the VM does not open Syncthing ports.
