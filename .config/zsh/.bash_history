sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay
cd yay-bin
makepkg -si
cd /home
cd
yay -S neovim
yay -S kitty
yay -S brave-browser
yay -S cmake
git clone --r https://github.com/hyprwm/hyprland
git clone --recursive https://github.com/hyprwm/hyprland
cd hyprland
make all && sudo make install
yay -S aquamarine
cd hyprland
make all && sudo make install
cd
yay -S aquamarine
cd hyprland
make all && sudo make install
cd
yay -S hyprlang hyprcursor hyprutils hyprgraphics hyprwayland-scanner
cd hyprland
make all && sudo make install
cd
yay -S re2 muparser
cd hyprland
make all && sudo make install
cd
yay -S ninja gcc meson libxcb xcb-proto xcb-util xcb-util-keysyms libxfixes libx11 libxcomposite libxrender libxcursor pixman wayland-protocols cario pango libxkbcommon xcb-util-wm xorg-xwayland libinput libliftoff libdisplay-info cpio tomlplusplus hyprlang-git hyprwayland-scanner-git hyprwire-git xcb-util-errors hyprutils-git glaze hyprgraphics-git hyprland-qtutils-git
yay -S hyprland
start-hyprland
yay -Rs hyprland
sudo rm -rf /hypr
yay -S hyprland
start-hyprland
sudo rf -rf dir ~/.config/hypr
sudo rm -rf dir ~/.config/hypr
yay -S ttf-jetbrains-mono-nerd noto-fonts noto-fons-emoji
yay -S ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
hyprland
start-hyprland
lspci -k | grep -A 2 -E "(VGA|DISPLAY)"
sudo pacman -S nvidia-open-dkms nvidia-utils lib32-nvidia-utils egl-wayland
sudo pacman -S nvidia-open-dkms nvidia-utils egl-wayland
start-hyprland
hyprland
yay -S libvulkan
hyprland
sudo pacman -Syu vulkan-icd-loader nvidia-utils lib32-vulkan-icd-loader lib32-nvidia-utils
yay -Syu vulkan-icd-loader nvidia-utils lib32-vulkan-icd-loader lib32-nvidia-utils
yay -Syu vulkan-icd-loader nvidia-utils lib32-vulkan-icd-loader lib32-nvidia-utils
yay -Syu vulkan-icd-loader nvidia-utils lib32-vulkan-icd-loader lib32-nvidia-utils
hyprland
sudo nvim /etc/pacman.conf
sudo pacman -S vulkan-icd-loader nvidia-utils lib32-vulkan-icd-loader lib32-nvidia-utils
yay -s nvidia-open-dkms
yay -s nvidia-open-dkms
hyprland
nvim /home/schulz/.cache/hyprland/hyprlandCrashReport73101.txt
hyprland
yay -Rs hyprland
yay -S nvidia-open-dkms
yay -S nvidia-utils
yay -S egl-wayland
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
yay -S lib32-nvidia-utils
sudo pacman -S nvidia-utils
sudo pacman -S hyprland
hyprland
start-hyprland
sudo pacman -S seatd
groups
addgroups
groupsadd -schultz
groups -schultz
groups -help
groups --help
logout
hyprland
yay -S thunar
sudo pacman -S xdg-desktop-portal-hyprland
yay -S waybar
yay -S wl-copy
sudo pacman -S wlcopy
sudo pacman -S wl-copy
sudo pacman -S wl-clipboard

hyprctl reload
pacman -S zsh
sudo pacman -S zsh
yay -S nvim
nvim .config/hypr/hyprland.conf
nvim .config/hypr/monitors.conf
nvim .config/hypr/hyprland.conf
yay -S hyprpolkitagent
yay -S swww
yay -S swaync
yay -S rofi
yay -S coolercontrol
yay -S coolercontrol
systemctl enable coolercontrold
systemctl enable coolercontrold
sudo systemctl enable --now coolercontrold
sudo systemctl status coolercontrold
hyprland
reboot
brave
yay -S nct6687d-dkms-git
sudo modprobe nct6687
yay -S nct6687d-dkms-git
sudo modprobe nct6687
echo "nct6687" | sudo tee /etc/modules-load.d/nct6687.conf
sudo sensors-detect
sensors
yay -S coolercontrol
sudo systemctl enable --now coolercontrold
lmn-sensors
lm-sensors
yay -S lm-sensors
sudo pacman -S lm-sensors
echo "blacklist nct6683" | sudo tee /etc/modprobe.d/nct6683.conf
echo "options nct6687 msi_fan_brute_force=1" | sudo tee /etc/modprobe.d/nct6687.conf
lsmod | grep nct
uname -r
sudo pacman -S linux-headers
sudo dkms autoinstall
sudo modprobe nct6687 force=1
lsmod | grep nct
sensorrs
sensors
nvim /home/schultz/.config/hypr/monitors.conf
nvim /home/schultz/.config/hypr/hyprland.conf
swww-daemon & disown
swww img Downloads/wallhaven-3qqdg6.jpg 
swww img set /home/schultz/Downloads/wallhaven-3qqdg6.jpg
swww img Downloads/wallhaven-3qqdg6.jpg
systemctl swww enable
sudo systemctl swww enable
sudo pacman -S swww
swww-daemon
swww-daemon & disown
waybar & disown
nvim .config/hypr/autostart.conf
chsh -s zsh
chsh -s zsh bin/bash
chsh -s zsh /bin/zsh
chsh -s zsh /bin/zsh
chsh -s /bin/zsh
logout
exit
nvim .config/hypr/hyprland.conf
sudo pacman -S zsh
log out
logout
exit
logout
hyprland
logout
hyprland
start-hyprland
