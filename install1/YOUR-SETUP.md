# Your Hyprland Setup - Quick Reference

This configuration is based on your actual installed packages from `pacman -Qetq`.

## 📊 Package Statistics

- **Base packages**: ~76 packages (without optional apps)
- **From AUR**: 27 packages
- **Official repos**: ~49 packages
- **Optional packages**: 5-10 (Steam, Spotify, OBS, etc. - now opt-in)
- **Installation groups**:
  - Minimal: 22 packages (core functionality)
  - Standard: 69 packages (recommended)
  - Full: 76 packages (everything except optional)

**Note:** Steam, Spotify, and OBS Studio are now in the OPTIONAL_PACKAGES section.
Uncomment them in `dependencies.conf` if you want to install them.

## 🔧 Your Specific Hardware/Software Stack

### GPU
- **NVIDIA** with open-source drivers (`nvidia-open-dkms`)
- Custom wlroots build with NVIDIA patches (`wlroots-nvidia`)

### System
- **Intel CPU** (`intel-ucode`)
- **EFI boot** with Limine bootloader
- **Custom fan control** (`nct6687d-dkms-git` for Nuvoton chip)

### Key Applications You Use

**Browsers:**
- Firefox (with pywalfox integration)
- Brave
- Chromium

**Development:**
- VS Code
- PyCharm
- Neovim
- Nano

**Communication:**
- Vesktop (Discord client)

**Media:**
- Spotify (with spicetify customization)
- Spotify-Qt
- MPV
- OBS Studio
- GPU Screen Recorder

**Utilities:**
- btop (system monitoring)
- Syncthing (file sync)
- Coolercontrol (hardware control)
- Snapper (snapshots)

## 🎨 Theming Setup

- **GTK Themes**: Adwaita, Orchis
- **Color Generation**: Matugen (Material Design)
- **Wallpaper**: Waypaper
- **Font**: JetBrains Mono Nerd Font, Monocraft

## 🔔 Notification System

You have **two** notification daemons:
- `mako` - Lightweight
- `swaync` - More feature-rich notification center

Pick one to use (comment out the other in dependencies.conf if you want).

## 📝 Notes on Your Package List

### Missing from Standard Lists
Your list is missing some common packages that might be installed as dependencies:
- `hyprland` itself (check if it's installed as a dependency)
- PipeWire audio stack (likely installed as dependencies)
- Basic screenshot tools (grim/slurp) - you use gpu-screen-recorder instead

### Unique Packages You Have
- `keypunch-git` - Typing practice tool
- `sad` - CLI search/replace tool
- `gpu-screen-recorder` - GPU-accelerated recording
- `hyprcap` - Hyprland capture tool
- `coolercontrol` - Advanced hardware control
- `nct6687d-dkms-git` - Specific hardware support

### TUI Tools
You prefer TUI (terminal UI) tools:
- `bluetui` - Bluetooth TUI
- `wifitui` - WiFi TUI
- Instead of GUI network managers

## 🚀 Installation Tips for Your Setup

### 0. Choose Your GPU Option

**You have NVIDIA**, so during installation:
- Select option 3 (NVIDIA GPU) when prompted
- OR edit `dependencies.conf` to keep the NVIDIA section uncommented

**If you switch to Intel iGPU:**
```bash
# Edit dependencies.conf
# Comment out NVIDIA section, uncomment Intel section
```

See [GPU-AND-OPTIONAL.md](GPU-AND-OPTIONAL.md) for full GPU configuration guide.

### 0.5. Enable Optional Packages (If Desired)

Edit `dependencies.conf` and uncomment what you want:
```bash
nano dependencies.conf

# Find OPTIONAL_PACKAGES section:
OPTIONAL_PACKAGES=(
    "steam"                           # Uncomment for gaming
    "spotify"                         # Uncomment for music
    "spotify-qt"
    "spicetify-cli"
    "obs-studio"                      # Uncomment for streaming
    "gpu-screen-recorder"             # Your NVIDIA can use this
)
```

The installer will automatically detect and prompt you to install uncommented packages.

### 1. NVIDIA Users - Important!
Before running the install script:
```bash
# You'll need to configure mkinitcpio for NVIDIA
sudo nano /etc/mkinitcpio.conf

# Add these modules:
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)

# After installation, regenerate:
sudo mkinitcpio -P
```

### 2. Install Order Recommendation

**First Run - Minimal:**
```bash
./install.sh
# Select: 1 (Minimal)
# Select GPU: 3 (NVIDIA)
```

**Second Run - Add AUR packages:**
```bash
# Edit hyprland-install.sh or run manually:
yay -S --needed brave-bin vesktop spotify-qt coolercontrol
```

**Third Run - Full setup:**
```bash
./install.sh
# Select: 3 (Full)
```

### 3. Post-Installation

**Configure coolercontrol:**
```bash
systemctl --user enable --now coolerctrld
```

**Setup Snapper:**
```bash
sudo snapper -c root create-config /
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
```

**Setup Syncthing:**
```bash
systemctl --user enable --now syncthing
```

**Setup ZRAM:**
```bash
sudo systemctl enable --now systemd-zram-setup@zram0.service
```

## 🎯 Dotfiles Structure Expected

Based on your packages, your dotfiles should include configs for:

```
~/.config/
├── hypr/
│   ├── hyprland.conf
│   ├── hypridle.conf
│   └── hyprlock.conf
├── waybar/
├── kitty/
├── mako/         (or swaync/)
├── wlogout/
├── btop/
├── neovim/
├── Code/         (VS Code)
├── fastfetch/
└── spicetify/
```

## ⚙️ Customization Notes

### To switch notification daemon:
```bash
# In dependencies.conf, comment out one:
INTERFACE_PACKAGES=(
    "mako"           # Use this one
    # "swaync"       # OR this one (not both)
)
```

### To add gaming packages:
```bash
# You already have Steam, add more if needed:
GAMING_PACKAGES=(
    "gamemode"
    "mangohud"
    "lutris"
)
```

### To add more development tools:
```bash
DEV_PACKAGES=(
    # ... existing packages ...
    "docker"
    "docker-compose"
    "postman-bin"
)
```

## 🐛 Known Issues for Your Setup

### NVIDIA + Wayland
- Requires `wlroots-nvidia` (you have it ✓)
- May need kernel parameters: `nvidia-drm.modeset=1`
- Some screen tearing possible in older games

### GPU Screen Recorder
- Requires CUDA/NVENC support
- Works best with NVIDIA 20-series or newer

### Multiple Notification Daemons
- Having both `mako` and `swaync` installed will conflict
- Choose one and disable the other

## 📚 Resources

- Your GPU recorder: https://git.dec05eba.com/gpu-screen-recorder
- Coolercontrol docs: https://gitlab.com/coolercontrol/coolercontrol
- Hyprland NVIDIA guide: https://wiki.hyprland.org/Nvidia/
- Snapper guide: https://wiki.archlinux.org/title/Snapper

## ✅ Testing Checklist for Your Setup

After installation, verify:
- [ ] NVIDIA drivers loaded (`nvidia-smi`)
- [ ] Hyprland starts with NVIDIA
- [ ] GPU screen recorder works
- [ ] Bluetooth (bluetui)
- [ ] WiFi (wifitui)
- [ ] Coolercontrol controls fans
- [ ] Spotify + Spicetify themes
- [ ] VS Code opens
- [ ] PyCharm works
- [ ] Syncthing syncs
- [ ] Snapper creates snapshots

---

**Last Updated**: Based on your package list
**Total Install Size**: ~8-10GB (varies with dependencies)
