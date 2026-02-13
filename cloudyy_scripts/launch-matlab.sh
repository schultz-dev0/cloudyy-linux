#!/bin/bash

# 1. The Hyprland/Wayland Fix (Prevents the blank grey window)
export _JAVA_AWT_WM_NONREPARENTING=1

# 2. Force X11 backend (MATLAB is unstable on native Wayland)
export GDK_BACKEND=x11

# 3. The GnuTLS Fix (From your previous success)
# Ensure this points to where you extracted the library
export LD_LIBRARY_PATH=$HOME/matlab-libs/usr/lib:$LD_LIBRARY_PATH

# 4. Launch MATLAB
# Using -desktop flag ensures it launches the full GUI, not terminal mode
exec ~/matlab/bin/matlab -desktop
