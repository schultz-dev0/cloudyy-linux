# GPU Options & Optional Packages Guide

## 🎮 GPU Options

The installation script now supports three GPU types with easy configuration.

### Option 1: Intel iGPU (Integrated Graphics)

**When to use:**
- Laptops with Intel processors
- Desktop systems using integrated graphics
- Systems without dedicated GPU

**What gets installed:**
```
mesa, lib32-mesa
vulkan-intel, lib32-vulkan-intel
intel-media-driver
libva-intel-driver
```

**To enable in dependencies.conf:**
```bash
# Comment out NVIDIA section:
# GPU_PACKAGES=(
#     "nvidia-open-dkms"
#     "wlroots-nvidia"
# )

# Uncomment Intel section:
GPU_PACKAGES=(
    "mesa"
    "lib32-mesa"
    "vulkan-intel"
    "lib32-vulkan-intel"
    "intel-media-driver"
    "libva-intel-driver"
)
```

### Option 2: AMD GPU

**When to use:**
- AMD Radeon graphics cards
- AMD APUs

**What gets installed:**
```
mesa, lib32-mesa
vulkan-radeon, lib32-vulkan-radeon
libva-mesa-driver, lib32-libva-mesa-driver
```

**To enable in dependencies.conf:**
```bash
# Comment out other GPU sections
# Uncomment AMD section:
GPU_PACKAGES=(
    "mesa"
    "lib32-mesa"
    "vulkan-radeon"
    "lib32-vulkan-radeon"
    "libva-mesa-driver"
    "lib32-libva-mesa-driver"
)
```

### Option 3: NVIDIA GPU (Current Default)

**When to use:**
- NVIDIA dedicated graphics cards
- Systems requiring NVIDIA CUDA/NVENC

**What gets installed:**
```
nvidia-open-dkms
nvidia-utils, lib32-nvidia-utils
nvidia-settings
wlroots-nvidia (AUR)
```

**Important NVIDIA Setup Steps:**

1. **After installation, configure mkinitcpio:**
```bash
sudo nano /etc/mkinitcpio.conf

# Add this line:
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

2. **Regenerate initramfs:**
```bash
sudo mkinitcpio -P
```

3. **Add kernel parameters (optional but recommended):**
```bash
sudo nano /etc/default/grub

# Add to GRUB_CMDLINE_LINUX_DEFAULT:
nvidia-drm.modeset=1

# Update GRUB:
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

4. **Reboot your system**

---

## 📦 Optional Packages

Steam, Spotify, OBS Studio, and GPU Screen Recorder are now **optional** and can be easily enabled/disabled.

### Making Packages Optional

**1. Edit dependencies.conf:**
```bash
nano dependencies.conf

# Find the OPTIONAL_PACKAGES section
# Uncomment what you want:
OPTIONAL_PACKAGES=(
    "steam"                           # Gaming
    "spotify"                         # Music
    "spotify-qt"
    "spicetify-cli"
    "obs-studio"                      # Streaming
    "gpu-screen-recorder"             # NVIDIA/AMD only
)
```

**2. Run the installer:**
```bash
./install.sh
# OR
./hyprland-install.sh
```

The script will automatically detect uncommented packages and prompt you to install them.

### Current Optional Packages

**Gaming:**
- `steam` - Valve's gaming platform

**Music:**
- `spotify` - Music streaming
- `spotify-qt` - Qt-based Spotify client
- `spicetify-cli` - Spotify customization tool

**Video/Streaming:**
- `obs-studio` - Streaming and recording
- `gpu-screen-recorder` - GPU-accelerated recording (NVIDIA/AMD only)

**Other:**
- `gimp` - Image editor
- `inkscape` - Vector graphics
- `blender` - 3D creation
- `libreoffice-fresh` - Office suite
- `vlc` - Media player
- And more...

---

## 🔄 Quick Configuration Examples

### Example 1: Intel Laptop Setup (Minimal)

```bash
# In dependencies.conf:

# 1. Use Intel iGPU
GPU_PACKAGES=(
    "mesa"
    "lib32-mesa"
    "vulkan-intel"
    "lib32-vulkan-intel"
    "intel-media-driver"
    "libva-intel-driver"
)

# 2. Skip optional packages (all commented out)
OPTIONAL_PACKAGES=(
    # "steam"
    # "spotify"
    # "obs-studio"
)
```

**Result:** Lightweight Hyprland setup for laptop, ~70 packages

### Example 2: Gaming Desktop with NVIDIA

```bash
# In dependencies.conf:

# 1. Keep NVIDIA drivers
GPU_PACKAGES=(
    "nvidia-open-dkms"
    "wlroots-nvidia"
)

# 2. Enable gaming and streaming
OPTIONAL_PACKAGES=(
    "steam"                           # ← Uncommented
    "obs-studio"                      # ← Uncommented
    "gpu-screen-recorder"             # ← Uncommented
    # "spotify"                        # Optional
)
```

**Result:** Full gaming setup with recording, ~75-80 packages

### Example 3: Music Production Workstation

```bash
# In dependencies.conf:

# 1. Intel or AMD GPU (your choice)
GPU_PACKAGES=(
    "mesa"
    "vulkan-intel"
    "intel-media-driver"
)

# 2. Enable audio apps
OPTIONAL_PACKAGES=(
    "spotify"                         # ← Uncommented
    "spotify-qt"                      # ← Uncommented
    "spicetify-cli"                   # ← Uncommented
    # "audacity"                       # Uncomment if you want
    # "steam"                          # Keep commented
)
```

**Result:** Audio-focused setup, ~72 packages

---

## ⚡ Quick Commands

### Check what GPU you have:
```bash
# Intel
lspci | grep VGA | grep Intel

# AMD
lspci | grep VGA | grep AMD

# NVIDIA
lspci | grep VGA | grep NVIDIA
```

### After installation, verify drivers:
```bash
# Intel
glxinfo | grep "OpenGL renderer"

# NVIDIA
nvidia-smi
```

### Install optional packages later:
```bash
# Uncomment in dependencies.conf, then:
./hyprland-install.sh
# Choose to skip hardware setup, just install optional packages
```

---

## 📊 Package Count by Configuration

| Configuration | Base Packages | Optional | Total |
|---------------|---------------|----------|-------|
| Minimal Intel | ~65 | 0 | ~65 |
| Minimal NVIDIA | ~70 | 0 | ~70 |
| Standard Intel | ~65 | 0 | ~65 |
| Standard NVIDIA | ~70 | 0 | ~70 |
| Gaming (NVIDIA) | ~70 | 5-8 | ~75-78 |
| All Apps | ~70 | 15+ | ~85+ |

---

## 🔍 Troubleshooting

### Intel iGPU not working:
```bash
# Check if drivers are loaded
lsmod | grep i915

# Check Xorg/Wayland log
cat ~/.hyprland.log | grep -i intel
```

### NVIDIA black screen:
```bash
# Make sure modules are in mkinitcpio.conf
grep nvidia /etc/mkinitcpio.conf

# Regenerate if needed
sudo mkinitcpio -P
```

### Optional packages not installing:
```bash
# Make sure they're uncommented (no # at the start)
grep -v "^#" dependencies.conf | grep -i steam

# Check if package exists
yay -Ss steam
```

---

## 💡 Pro Tips

1. **Start with minimal**: Install base system first, add optional packages later
2. **Test GPU drivers**: Make sure graphics work before installing heavy packages
3. **One GPU at a time**: Only have ONE GPU_PACKAGES section uncommented
4. **Check AUR availability**: Some AUR packages may not be available yet
5. **Regular updates**: Keep dependencies.conf updated as packages change

---

## 📝 Notes

- GPU screen recorder only works with NVIDIA/AMD (requires hardware encoding)
- Spotify setup may require additional configuration with spicetify
- Steam requires multilib repository enabled in pacman.conf
- OBS may need additional plugins depending on your streaming needs

---

**Last Updated**: 2024
**Compatible with**: Arch Linux, Hyprland
