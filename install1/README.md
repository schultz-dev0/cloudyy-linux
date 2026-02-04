# Hyprland Installation Scripts for Arch Linux

This is a complete installation script suite for setting up Hyprland on Arch Linux with hardware detection, dependency management, and dotfiles deployment.

## 📁 Project Structure

```
hyprland-setup/
├── install.sh              # Master installer
├── hyprland-install.sh     # Hardware & package installation
├── deploy-dotfiles.sh      # Configuration deployment
├── dependencies.conf       # Package definitions (EDIT THIS!)
├── test-install.sh         # Validation script
├── README.md               # This file
└── TESTING.md             # Comprehensive testing guide
```

## 🎯 Key Features

- **Easy to customize** - All packages defined in `dependencies.conf`
- **Multiple GPU support** - Intel iGPU, AMD, or NVIDIA (with easy switching)
- **Modular installation** - Choose minimal, standard, or full setup
- **Optional packages** - Steam, Spotify, OBS are opt-in
- **Hardware detection** - Auto-detects CPU and prompts for GPU type
- **Safe deployment** - Backs up existing configs before changes
- **Validated** - Includes test script to catch issues early

## 📋 What This Does

1. **Hardware Detection & Driver Installation**
   - Detects CPU and installs appropriate microcode (Intel/AMD)
   - Installs GPU drivers (Intel/AMD/NVIDIA/Hybrid)
   - Installs wireless and Bluetooth firmware
   - Installs Hyprland and essential Wayland packages

2. **Dotfiles Deployment**
   - Clones or uses local dotfiles repository
   - Backs up existing configurations
   - Deploys configurations via symlink or copy
   - Installs custom scripts to ~/.local/bin

## 🚀 Quick Start

### Before Installation - Test Your Scripts!

```bash
# First, validate everything is correct
chmod +x test-install.sh
./test-install.sh
```

**All tests should pass before proceeding!** ✅

### Installation Methods

### Option 1: Complete Installation (Recommended)
```bash
# Make the master script executable
chmod +x install.sh

# Run the complete installation
./install.sh
```

### Option 2: Step-by-Step Installation
```bash
# Step 1: Hardware and drivers
chmod +x hyprland-install.sh
./hyprland-install.sh

# Step 2: Deploy dotfiles
chmod +x deploy-dotfiles.sh
./deploy-dotfiles.sh
```

## 📁 Script Overview

### `install.sh` (Master Script)
- Runs both installation steps in sequence
- Checks for prerequisites
- Provides a complete end-to-end setup

### `hyprland-install.sh` (Hardware Setup)
- Updates system packages
- Installs `yay` AUR helper if not present
- Prompts for:
  - CPU type (Intel/AMD)
  - GPU configuration (Intel/AMD/NVIDIA/Hybrid)
  - Wireless firmware needs
- Installs Hyprland and essential packages

### `deploy-dotfiles.sh` (Configuration Deployment)
- Clones or uses local dotfiles
- Backs up existing configurations
- Deploys configs via symlink or copy
- Installs scripts to PATH

## 🔧 Prerequisites

- Fresh or existing Arch Linux installation
- User account with sudo privileges
- Internet connection
- (Optional) A dotfiles repository

## 📦 Packages Installed

### Package Count by Configuration
- **Minimal**: ~22 packages (core Hyprland only)
- **Standard**: ~69 packages (recommended daily driver)
- **Full**: ~76 packages (everything except optional apps)
- **+ Optional**: Add 5-15 more packages as needed

### GPU Options (Choose One)

**Intel iGPU** - Integrated graphics
- mesa, vulkan-intel, intel-media-driver
- Best for laptops and systems without dedicated GPU

**AMD GPU** - Radeon graphics
- mesa, vulkan-radeon, libva-mesa-driver
- For AMD graphics cards and APUs

**NVIDIA GPU** - GeForce/Quadro
- nvidia-open-dkms, wlroots-nvidia
- Requires additional configuration (see GPU-AND-OPTIONAL.md)

### Optional Packages (Opt-in)

These are **commented out by default**. Uncomment in `dependencies.conf` to install:
- `steam` - Gaming platform
- `spotify`, `spotify-qt`, `spicetify-cli` - Music streaming
- `obs-studio` - Streaming and recording
- `gpu-screen-recorder` - GPU-accelerated recording (NVIDIA/AMD)
- And more (gimp, inkscape, vlc, etc.)

See **[GPU-AND-OPTIONAL.md](GPU-AND-OPTIONAL.md)** for detailed configuration guide.

### Essential Hyprland Packages
- `hyprland` - The Hyprland compositor
- `kitty` - Terminal emulator
- `waybar` - Status bar
- `wofi` - Application launcher
- `dunst` - Notification daemon
- `xdg-desktop-portal-hyprland` - Portal for Wayland
- `qt5-wayland` & `qt6-wayland` - Qt Wayland support
- `pipewire` & `wireplumber` - Audio system
- `grim` & `slurp` - Screenshot tools
- `wl-clipboard` - Clipboard manager

### Hardware-Specific
**Choose your GPU type during installation:**
- **Intel iGPU**: `mesa`, `vulkan-intel`, `intel-media-driver`
- **AMD GPU**: `mesa`, `vulkan-radeon`, `libva-mesa-driver`
- **NVIDIA GPU**: `nvidia-open-dkms`, `wlroots-nvidia`, `nvidia-utils`

**CPU Microcode** (auto-detected):
- **Intel CPU**: `intel-ucode`
- **AMD CPU**: `amd-ucode`

**Wireless**: `linux-firmware`, `broadcom-wl-dkms` (if needed)

## 📝 Dotfiles Structure

Your dotfiles repository should have a structure like:

```
dotfiles/
├── hypr/
│   ├── hyprland.conf
│   └── ...
├── waybar/
│   ├── config
│   └── style.css
├── kitty/
│   └── kitty.conf
├── wofi/
│   └── config
├── dunst/
│   └── dunstrc
└── scripts/
    ├── screenshot.sh
    └── ...
```

## 🎯 Post-Installation

After running the scripts:

1. **Log out** of your current session
2. **Select Hyprland** from your display manager (GDM, SDDM, LightDM)
3. **Log in** and start using Hyprland

Or start Hyprland manually from TTY:
```bash
Hyprland
```

## 🔄 Backup Information

- Existing configurations are backed up to: `~/.config_backup_YYYYMMDD_HHMMSS/`
- You can restore backups by copying files back to `~/.config/`

## 🐛 Troubleshooting

For comprehensive testing and troubleshooting information, see **[TESTING.md](TESTING.md)**.

Quick fixes:

### AUR Helper Installation Fails
```bash
# Manually install yay
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

### NVIDIA Issues
- Make sure to add NVIDIA modules to `/etc/mkinitcpio.conf`:
  ```
  MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
  ```
- Regenerate initramfs: `sudo mkinitcpio -P`
- Reboot your system

### Wireless Not Working (MacBook)
```bash
# For Broadcom wireless
sudo pacman -S broadcom-wl-dkms
sudo modprobe wl

# Or try
yay -S broadcom-wl-dkms
```

### Hyprland Won't Start
- Check logs: `cat ~/.hyprland.log`
- Make sure all GPU drivers are properly installed
- Try starting from TTY: `Hyprland`

## ⚙️ Customization

### Editing Dependencies

**The `dependencies.conf` file is designed to be easily edited!**

1. Open `dependencies.conf` in any text editor
2. Find the section you want to modify (clearly labeled with comments)
3. Add or remove packages from the arrays

**Example - Adding a package:**
```bash
# Open the file
nano dependencies.conf

# Find the APP_PACKAGES section and add your package:
APP_PACKAGES=(
    "firefox"
    "chromium"
    "discord"
    "spotify-launcher"
    "mpv"
    "imv"
    "your-new-package"    # Add this line
)
```

**Example - Removing a package:**
```bash
# Just comment it out or delete the line:
APP_PACKAGES=(
    "firefox"
    # "chromium"    # Commented out - won't be installed
    "discord"
)
```

**Example - Adding a whole new category:**
```bash
# Add at the bottom of dependencies.conf:
GAMING_PACKAGES=(
    "steam"
    "lutris"
    "gamemode"
    "mangohud"
)

# Then add to FULL_GROUP:
FULL_GROUP=(
    "${CORE_PACKAGES[@]}"
    # ... other packages ...
    "${GAMING_PACKAGES[@]}"    # Add your new category
)
```

### Testing Your Changes

After editing `dependencies.conf`, always test:
```bash
./test-install.sh
```

This validates your syntax and checks for common errors.

## 📚 Additional Resources

**Documentation:**
- [GPU-AND-OPTIONAL.md](GPU-AND-OPTIONAL.md) - GPU setup and optional packages guide
- [TESTING.md](TESTING.md) - Comprehensive testing guide
- [YOUR-SETUP.md](YOUR-SETUP.md) - Your specific configuration notes

**External Resources:**
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [Arch Wiki - Hyprland](https://wiki.archlinux.org/title/Hyprland)
- [r/hyprland](https://reddit.com/r/hyprland)

## ⚠️ Important Notes

- **DO NOT run as root** - Run as a normal user with sudo privileges
- The scripts will prompt you for decisions - read carefully
- Installation time varies based on internet speed and hardware
- Some changes require a system reboot (especially NVIDIA drivers)

## 📄 License

These scripts are provided as-is for educational and personal use.

## 🤝 Contributing

Feel free to modify these scripts for your own setup. Suggestions for improvements are welcome!

---

**Enjoy your new Hyprland setup! 🎉**
