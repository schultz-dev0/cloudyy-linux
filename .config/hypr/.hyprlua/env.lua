-- Environment variables
-- Sources: hyprland.conf (NVIDIA block) + source/lookandfeel.conf (cursor)

-- NVIDIA (injected by cloudyy-linux installer)
hl.env("LIBVA_DRIVER_NAME",         "nvidia")
hl.env("GBM_BACKEND",               "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS",   "1")
hl.env("NVD_BACKEND",               "direct")

-- Cursor size
hl.env("XCURSOR_SIZE",    "24")
hl.env("HYPRCURSOR_SIZE", "24")
