# Testing Guide for Hyprland Installation Scripts

This guide explains how to safely test the installation scripts without breaking your system.

## 📋 Table of Contents

1. [Quick Validation](#quick-validation)
2. [VM Testing (Recommended)](#vm-testing-recommended)
3. [Docker Testing (Limited)](#docker-testing-limited)
4. [Test Installation on Real Hardware](#test-installation-on-real-hardware)
5. [Troubleshooting Tests](#troubleshooting-tests)

---

## Quick Validation

Before doing anything else, run the test script to validate all files:

```bash
chmod +x test-install.sh
./test-install.sh
```

This will check:
- ✓ All scripts exist and are executable
- ✓ Syntax is valid
- ✓ Dependencies are properly defined
- ✓ Package arrays are correctly structured
- ✓ No common errors in the code

**Expected Result:** All tests should pass (green output)

---

## VM Testing (Recommended)

This is the **safest and most reliable** way to test the scripts.

### Option 1: VirtualBox

1. **Download Arch ISO**
   ```bash
   wget https://archlinux.org/download/
   ```

2. **Create a new VM in VirtualBox:**
   - Type: Arch Linux (64-bit)
   - RAM: 4GB minimum (8GB recommended)
   - Disk: 20GB minimum
   - Enable 3D acceleration
   - Network: NAT or Bridged

3. **Install Arch Linux:**
   ```bash
   # Quick Arch install (use archinstall for easier setup)
   archinstall
   ```

4. **Transfer your scripts to the VM:**
   
   **Method A: Shared Folder**
   - Set up shared folder in VirtualBox
   - Mount it in the VM
   
   **Method B: Git**
   ```bash
   # Push to GitHub first, then clone in VM
   git clone https://github.com/yourusername/hyprland-setup.git
   cd hyprland-setup
   ```
   
   **Method C: SCP**
   ```bash
   # From host machine
   scp -r ./*.sh user@vm-ip:~/hyprland-setup/
   ```

5. **Run the installation:**
   ```bash
   cd hyprland-setup
   ./test-install.sh    # Validate first
   ./install.sh         # Run full installation
   ```

6. **Test the installation:**
   - Reboot the VM
   - Select Hyprland from display manager
   - Test all features (see Feature Testing below)

### Option 2: QEMU/KVM

```bash
# Install QEMU
sudo pacman -S qemu-full virt-manager

# Create VM using virt-manager GUI
# Follow similar steps as VirtualBox
```

---

## Docker Testing (Limited)

Docker can test package installation but **cannot test Hyprland itself** (no display/GUI).

### Create Test Container

```bash
# Create Dockerfile
cat > Dockerfile.test <<'EOF'
FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm sudo base-devel git

RUN useradd -m -G wheel testuser && \
    echo "testuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER testuser
WORKDIR /home/testuser

COPY --chown=testuser:testuser . ./hyprland-setup/

RUN cd hyprland-setup && \
    chmod +x test-install.sh && \
    ./test-install.sh
EOF

# Build and run
docker build -f Dockerfile.test -t hyprland-test .
docker run -it hyprland-test bash

# Inside container
cd hyprland-setup
./hyprland-install.sh
```

**Limitations:**
- No GUI testing
- No Wayland/display testing
- Only validates package installation

---

## Test Installation on Real Hardware

⚠️ **Only do this if you're comfortable with potentially breaking your system**

### Pre-Installation Backup

```bash
# Backup current configs
mkdir -p ~/backup_before_hyprland
cp -r ~/.config ~/backup_before_hyprland/
cp ~/.bashrc ~/backup_before_hyprland/
cp ~/.zshrc ~/backup_before_hyprland/ 2>/dev/null || true

# Create system snapshot (if using Btrfs/Timeshift)
sudo timeshift --create --comments "Before Hyprland installation"
```

### Safe Testing Approach

```bash
# 1. Run validation first
./test-install.sh

# 2. Review what will be installed
cat dependencies.conf

# 3. Do a dry run (comment out actual install commands)
# Edit scripts and add 'echo' before pacman/yay commands for testing

# 4. Start with minimal installation
./install.sh
# Choose option 1 (Minimal) when prompted

# 5. If minimal works, try standard
# If something breaks, restore from backup
```

### Rollback Plan

If something goes wrong:

```bash
# 1. Restore configs
rm -rf ~/.config
cp -r ~/backup_before_hyprland/.config ~/

# 2. Restore shell configs
cp ~/backup_before_hyprland/.bashrc ~/
cp ~/backup_before_hyprland/.zshrc ~/ 2>/dev/null || true

# 3. Remove installed packages (optional)
sudo pacman -Rns hyprland waybar wofi dunst
```

---

## Feature Testing Checklist

After installation, test these features:

### Basic Functionality
- [ ] Hyprland starts without errors
- [ ] Super key opens application launcher (wofi)
- [ ] Can open terminal (Super+Enter)
- [ ] Waybar displays correctly
- [ ] Can switch workspaces (Super+1-9)
- [ ] Window tiling works

### Hardware
- [ ] Display resolution is correct
- [ ] Graphics acceleration works (check with `glxinfo`)
- [ ] Audio plays (test with `speaker-test`)
- [ ] Volume controls work (PulseAudio/PipeWire)
- [ ] Brightness controls work (if laptop)
- [ ] Wi-Fi works
- [ ] Bluetooth works (if applicable)

### Interface Components
- [ ] Screenshots work (Super+Shift+S or custom keybind)
- [ ] Clipboard works (copy/paste)
- [ ] Notifications appear (test with `notify-send "Test"`)
- [ ] File manager opens
- [ ] Theme looks correct

### Applications
- [ ] Terminal emulator works
- [ ] Web browser launches
- [ ] Can launch installed applications

### Dotfiles
- [ ] Configs are in correct locations (`~/.config/`)
- [ ] Scripts are executable (`~/.local/bin/`)
- [ ] Custom keybindings work
- [ ] Startup applications launch

---

## Automated Testing Script

Create a quick automated test:

```bash
#!/bin/bash
# quick-test.sh

echo "Testing basic functionality..."

# Test 1: Check if Hyprland is installed
if command -v Hyprland &>/dev/null; then
    echo "✓ Hyprland installed"
else
    echo "✗ Hyprland not found"
fi

# Test 2: Check configs exist
if [ -d "$HOME/.config/hypr" ]; then
    echo "✓ Hyprland config exists"
else
    echo "✗ Hyprland config missing"
fi

# Test 3: Check waybar
if command -v waybar &>/dev/null; then
    echo "✓ Waybar installed"
else
    echo "✗ Waybar not found"
fi

# Test 4: Check audio
if command -v pipewire &>/dev/null; then
    echo "✓ PipeWire installed"
else
    echo "✗ PipeWire not found"
fi

# Test 5: Check essential tools
for tool in wofi dunst grim slurp; do
    if command -v $tool &>/dev/null; then
        echo "✓ $tool installed"
    else
        echo "✗ $tool not found"
    fi
done
```

---

## Troubleshooting Tests

### If Hyprland won't start:

```bash
# Check logs
cat ~/.hyprland.log

# Test from TTY
Ctrl+Alt+F2  # Switch to TTY
Hyprland     # Try to start manually
```

### If packages fail to install:

```bash
# Update mirrors
sudo pacman -Syy

# Clear package cache
sudo pacman -Scc

# Check for conflicts
pacman -Qi package-name
```

### If AUR packages fail:

```bash
# Reinstall yay
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

---

## Testing Specific Features

### Test Dependencies Loading

```bash
# Verify dependencies.conf is sourced correctly
bash -c 'source ./dependencies.conf && echo "Core packages: ${#CORE_PACKAGES[@]}"'
```

### Test Package Selection

```bash
# Manually test the package selection logic
source dependencies.conf
echo "Minimal: ${#MINIMAL_GROUP[@]} packages"
echo "Standard: ${#STANDARD_GROUP[@]} packages"
echo "Full: ${#FULL_GROUP[@]} packages"
```

### Test Dry Run

Edit `hyprland-install.sh` temporarily:

```bash
# Change line:
sudo pacman -S --needed --noconfirm "${UNIQUE_PACKAGES[@]}"

# To:
echo "Would install: ${UNIQUE_PACKAGES[@]}"
```

Then run to see what would be installed without actually installing.

---

## Best Practices

1. **Always run `test-install.sh` first**
2. **Use VM for initial testing**
3. **Start with minimal installation**
4. **Keep backups of working configurations**
5. **Test one component at a time**
6. **Document any issues you encounter**
7. **Check logs when something fails**

---

## Success Criteria

Your installation is successful if:

- ✅ All tests in `test-install.sh` pass
- ✅ Hyprland starts without errors
- ✅ All your hardware works
- ✅ You can perform basic window management
- ✅ Essential apps launch correctly
- ✅ No error messages in `~/.hyprland.log`

---

## Getting Help

If tests fail:

1. Check the error messages carefully
2. Review `~/.hyprland.log`
3. Check Arch Wiki: https://wiki.archlinux.org/title/Hyprland
4. Check Hyprland Wiki: https://wiki.hyprland.org/
5. Search for specific error messages online

---

## Next Steps After Successful Testing

1. Commit your scripts to Git
2. Document your specific hardware setup
3. Create a backup of working configs
4. Customize your setup further
5. Share your setup with others!
