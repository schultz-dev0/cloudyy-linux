-- Shared variables and environment
-- Sources: source/variables.conf + legacy env.lua

terminal = "kitty"
browser = "zen-browser"
mainMod = "SUPER"
fileManager = "thunar"

hl.env("BROWSER", browser)
hl.env("TERMINAL", terminal)
hl.env("FILEMANAGER", fileManager)

hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("NVD_BACKEND", "direct")
