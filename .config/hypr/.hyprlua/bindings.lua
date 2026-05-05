-- Keybindings
-- Sources: user-configs/user_bindings.conf + user-configs/user_variables.conf
-- Bind flag mapping: binde→repeating, bindl→locked, bindel→locked+repeating, bindm→mouse

local mainMod = "SUPER"
local scripts = os.getenv("HOME") .. "/cloudyy_scripts"

-- ── Tiling ────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + W",       hl.dsp.window.close(),                { desc = "Kill active window" })
hl.bind(mainMod .. " + T",       hl.dsp.window.float(),                { desc = "Toggle floating" })
hl.bind(mainMod .. " + F",       hl.dsp.window.fullscreen(),           { desc = "Toggle fullscreen" })

-- ── Apps ──────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + Return",  hl.dsp.exec_cmd("uwsm-app kitty"),    { desc = "Open terminal" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("thunar"),          { desc = "Open filemanager" })
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("brave --new-window"), { desc = "Open browser" })
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("uwsm-app spotify"), { desc = "Open Spotify" })
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("uwsm-app obs"),    { desc = "Open OBS" })

-- ── Custom apps ───────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd(scripts .. "/cloudyy-other/keypunch"), { desc = "Launch keypunch" })
hl.bind("ALT + 1", hl.dsp.exec_cmd("uwsm-app -- " .. scripts .. "/cloud-center --wifi"),        { desc = "Wi-Fi Manager" })
hl.bind("ALT + 2", hl.dsp.exec_cmd("uwsm-app -- " .. scripts .. "/cloud-center --bluetooth"),   { desc = "Bluetooth Manager" })
hl.bind("ALT + 3", hl.dsp.exec_cmd("uwsm-app -- " .. scripts .. "/cloud-center --audio"),       { desc = "Audio Mixer" })
hl.bind("ALT + 4", hl.dsp.exec_cmd("uwsm-app python3 " .. scripts .. "/cloud-center-v2/cloud-center.py"), { desc = "Cloud Center" })
hl.bind("ALT + 6", hl.dsp.exec_cmd("pkill -x visinput || " .. scripts .. "/cloudyy-other/visinput"), { desc = "Visual input toggle" })
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd(scripts .. "/cloudyy-other/hyprdock hyprdock -s"), { desc = "Open spotlight search" })

-- ── Rofi ──────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd(scripts .. "/rofi/main.sh || pkill rofi"),             { desc = "Rofi menu launch" })
hl.bind("ALT + Space",               hl.dsp.exec_cmd(scripts .. "/rofi/appearance.sh --select || pkill rofi"), { desc = "Rofi theme menu" })
hl.bind(mainMod .. " + Space",       hl.dsp.exec_cmd(scripts .. "/rofi/applications.sh || pkill rofi"),     { desc = "Open rofi applications" })

-- ── Utilities ─────────────────────────────────────────────────────────────────

hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprcap shot region -z -w"),          { desc = "Screenshot region and save" })
hl.bind("Print",         hl.dsp.exec_cmd("hyprcap shot region -z -c -n"),        { desc = "Screenshot to clipboard" })
hl.bind("ALT + Print",   hl.dsp.exec_cmd("hyprcap rec region -c -w"),         { desc = "Start screen recording" })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("hyprpicker -a || pkill hyprpicker"), { desc = "Colour picker" })
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(scripts .. "/theme_controller.sh random"), { desc = "Random wallpaper" })

-- ── Appearance ────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(scripts .. "/theme_controller.sh toggle"), { desc = "Toggle light/dark theme" })

-- ── Volume (laptop keys) ──────────────────────────────────────────────────────

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh up"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh mute"), { locked = true })

-- Volume — arrow keys
hl.bind(mainMod .. " + up",   hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh up"),   { repeating = true })
hl.bind(mainMod .. " + down", hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh down"), { repeating = true })
hl.bind(mainMod .. " + m",    hl.dsp.exec_cmd(scripts .. "/sliders/volume-slider.sh mute"), { locked = true })

-- ── Media ─────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("playerctl next"),        { desc = "Next song" })
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("playerctl previous"),    { desc = "Previous song" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("playerctl play-pause"),  { desc = "Play/pause" })

hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),        { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"),  { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),    { locked = true })

-- ── Brightness ────────────────────────────────────────────────────────────────

hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(scripts .. "/sliders/brightness-slider.sh up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(scripts .. "/sliders/brightness-slider.sh down"), { locked = true, repeating = true })

-- ── Notifications (quickshell IPC) ───────────────────────────────────────────

hl.bind(mainMod .. " + N",           hl.dsp.exec_cmd("qs ipc call notifs toggle"),      { desc = "Toggle notif center" })
hl.bind(mainMod .. " + SHIFT + N",   hl.dsp.exec_cmd("qs ipc call notifs dnd"),         { desc = "Toggle DND" })
hl.bind(mainMod .. " + CTRL + N",    hl.dsp.exec_cmd("qs ipc call notifs dismissLast"), { desc = "Close last notif" })

-- ── Window management ─────────────────────────────────────────────────────────

hl.bind("ALT + Tab",     hl.dsp.window.cycle_next(),                                  { desc = "Cycle windows" })
hl.bind(mainMod .. " + I", hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }), { desc = "Toggle opacity" })

-- Focus (arrow keys)
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.focus({ direction = "left"  }), { repeating = true, desc = "Focus left" })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.focus({ direction = "right" }), { repeating = true, desc = "Focus right" })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.focus({ direction = "up"    }), { repeating = true, desc = "Focus up" })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.focus({ direction = "down"  }), { repeating = true, desc = "Focus down" })

-- Move window (arrow keys)
hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.move({ direction = "left"  }), { repeating = true, desc = "Move window left" })
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }), { repeating = true, desc = "Move window right" })
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.move({ direction = "up"    }), { repeating = true, desc = "Move window up" })
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.move({ direction = "down"  }), { repeating = true, desc = "Move window down" })

-- ── Clipboard ─────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + CTRL + Space", hl.dsp.exec_cmd("uwsm-app cliphist list | rofi -dmenu | cliphist decode | wl-copy"), { desc = "Open clipboard history" })
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(os.getenv("HOME") .. "/cloudyy_scripts/clipboard/clipboard.sh copy"),  { desc = "Universal copy" })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(os.getenv("HOME") .. "/cloudyy_scripts/clipboard/clipboard.sh paste"), { desc = "Universal paste" })

-- ── Workspaces ────────────────────────────────────────────────────────────────

for i = 1, 10 do
    local key = i % 10  -- 10 → key 0
    hl.bind(mainMod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { desc = "Toggle scratchpad" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { desc = "Move to scratchpad" })

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { mouse = true })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { mouse = true })

-- Move/resize windows with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Misc ──────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { desc = "Reload Hyprland" })

-- --- Cloud Center Additions (managed by Cloud Center) ---
hl.bind("SUPER + CTRL + K", hl.dsp.exec_cmd("rusty_keys"))
-- --- End Cloud Center Additions ---
hl.bind(mainMod .. " SHIFT + E", hl.dsp.exec_cmd("~/cloudyy_scripts/clipboard/text_extract.sh"), { desc = "Live Text Extraction" })
