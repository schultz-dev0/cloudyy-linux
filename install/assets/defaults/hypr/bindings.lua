-- Keybindings
-- Source: active Lua bindings

local mainMod = "SUPER"

-- ── Tiling ────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + W", hl.dsp.window.close(), { desc = "Kill active window" })
hl.bind(mainMod .. " + T", hl.dsp.window.float(), { desc = "Toggle floating" })
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(), { desc = "Toggle fullscreen" })

-- ── Apps ──────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd("cloudyy-terminal-cwd-walk"), { desc = "Open terminal in focused dir" })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.exec_cmd("cloudyy-terminal-fm-walk"), { desc = "Open filemanager" })
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(browser .. " --new-window"), { desc = "Open browser" })
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("uwsm-app spotify"), { desc = "Open Spotify" })
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("uwsm-app obs"), { desc = "Open OBS" })

-- ── Custom apps ───────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("uwsm-app keypunch"), { desc = "Open typing practice (Keypunch)" })
hl.bind("ALT + 1", hl.dsp.exec_cmd("uwsm-app -- cloudyy-center --wifi"), { desc = "Wi-Fi Manager" })
hl.bind("ALT + 2", hl.dsp.exec_cmd("uwsm-app -- cloudyy-center --bluetooth"), { desc = "Bluetooth Manager" })
hl.bind("ALT + 3", hl.dsp.exec_cmd("uwsm-app -- cloudyy-center --audio"), { desc = "Audio Mixer" })
hl.bind("ALT + 4", hl.dsp.exec_cmd("uwsm-app -- cloudyy-center"), { desc = "Cloud Center" })
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("quickshell ipc call spotlight toggle"), { desc = "Open spotlight search" })
hl.bind(
	mainMod .. " + CTRL + C",
	hl.dsp.exec_cmd("quickshell ipc call calculator toggle"),
	{ desc = "Open calculator" }
)
hl.bind(
	mainMod .. " + Tab",
	hl.dsp.exec_cmd("quickshell ipc call overview open"),
	{ desc = "Show all workspaces (hold Super, keep pressing Tab to cycle)" }
)
hl.bind(
	mainMod .. " + SHIFT + Tab",
	hl.dsp.exec_cmd("quickshell ipc call overview cyclePrevious"),
	{ desc = "Cycle workspace overview backward" }
)
hl.bind("Super_L", hl.dsp.exec_cmd("quickshell ipc call overview release"), {
	desc = "Confirm workspace pick (release Super after Tab)",
	release = true,
	transparent = true,
	ignore_mods = true,
})
hl.bind("Super_R", hl.dsp.exec_cmd("quickshell ipc call overview release"), {
	desc = "Confirm workspace pick (release Super after Tab)",
	release = true,
	transparent = true,
	ignore_mods = true,
})
hl.bind(mainMod .. "+ CTRL + S", hl.dsp.exec_cmd("stochos"), { desc = "Open stochos for mouseless navigation" })

-- ── Spotlight / Command Center (Quickshell) ───────────────────────────────────

hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("qs ipc call spotlight command"), { desc = "Command Center" })
hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd("qs ipc call applibrary open"), { desc = "App menu" })
hl.bind("ALT + Space", hl.dsp.exec_cmd("qs ipc call spotlight wallpaper"), { desc = "Wallpaper menu" })

-- ── Utilities ─────────────────────────────────────────────────────────────────

hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprcap shot region -z -w"), { desc = "Screenshot region and save" })
hl.bind("Print", hl.dsp.exec_cmd("cloudyy-screenshot-capture --screenshot"), { desc = "Screenshot popup (island)" })
hl.bind("ALT + Print", hl.dsp.exec_cmd("cloudyy-screenshot-capture --record"), { desc = "Screen record (island)" })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd("hyprpicker -a || pkill hyprpicker"), { desc = "Colour picker" })
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("cloudyy-theme random"), { desc = "Random wallpaper" })

-- ── Appearance ────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("cloudyy-theme toggle"), { desc = "Toggle light/dark theme" })

-- ── Volume (laptop keys) ──────────────────────────────────────────────────────

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("cloudyy-slider-volume up"),
	{ locked = true, repeating = true, desc = "Volume up (media key)" }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("cloudyy-slider-volume down"),
	{ locked = true, repeating = true, desc = "Volume down (media key)" }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("cloudyy-slider-volume mute"), { locked = true, desc = "Mute (media key)" })

hl.bind(mainMod .. " + up", hl.dsp.exec_cmd("cloudyy-slider-volume up"), { repeating = true, desc = "Volume up" })
hl.bind(mainMod .. " + down", hl.dsp.exec_cmd("cloudyy-slider-volume down"), { repeating = true, desc = "Volume down" })
hl.bind(mainMod .. " + m", hl.dsp.exec_cmd("cloudyy-slider-volume mute"), { locked = true, desc = "Mute" })

-- ── Media ─────────────────────────────────────────────────────────────────────

hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("playerctl next"), { desc = "Next song" })
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("playerctl previous"), { desc = "Previous song" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("playerctl play-pause"), { desc = "Play/pause" })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, desc = "Next track (media key)" })
hl.bind(
	"XF86AudioPause",
	hl.dsp.exec_cmd("playerctl play-pause"),
	{ locked = true, desc = "Pause playback (media key)" }
)
hl.bind(
	"XF86AudioPlay",
	hl.dsp.exec_cmd("playerctl play-pause"),
	{ locked = true, desc = "Play/resume playback (media key)" }
)
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, desc = "Previous track (media key)" })

-- ── Brightness ────────────────────────────────────────────────────────────────

hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("cloudyy-slider-brightness up"),
	{ locked = true, repeating = true, desc = "Brightness up (media key)" }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("cloudyy-slider-brightness down"),
	{ locked = true, repeating = true, desc = "Brightness down" }
)

-- ── Notifications (quickshell IPC) ───────────────────────────────────────────

hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notifs toggle"), { desc = "Toggle notif center" })
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("qs ipc call notifs dnd"), { desc = "Toggle DND" })
hl.bind(mainMod .. " + CTRL + N", hl.dsp.exec_cmd("qs ipc call notifs clearAll"), { desc = "Clear all notifications" })
hl.bind(mainMod .. " + ALT + N", hl.dsp.exec_cmd("cloudyy-slider-nightlight toggle"), { desc = "Toggle night light" })

-- ── quickshell ─────────────────────────────────────────────────────────

hl.bind(
	mainMod .. " + CTRL + M",
	hl.dsp.exec_cmd("qs ipc call system toggle"),
	{ desc = "Toggle system stats overlay" }
)
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("quickshell ipc call timer toggle"), { desc = "Toggle timer panel" })
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("quickshell ipc call calendar toggle"), { desc = "Toggle calendar" })

-- ── Window Management ─────────────────────────────────────────────────────────

hl.bind("ALT + Tab", hl.dsp.window.cycle_next(), { desc = "Cycle windows" })
hl.bind(
	mainMod .. " + I",
	hl.dsp.window.set_prop({ prop = "opaque", value = "toggle" }),
	{ desc = "Toggle window transparency" }
)
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.focus({ direction = "left" }), { repeating = true, desc = "Focus left" })
hl.bind(
	mainMod .. " + SHIFT + right",
	hl.dsp.focus({ direction = "right" }),
	{ repeating = true, desc = "Focus right" }
)
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.focus({ direction = "up" }), { repeating = true, desc = "Focus up" })
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.focus({ direction = "down" }), { repeating = true, desc = "Focus down" })
hl.bind(
	mainMod .. " + CTRL + left",
	hl.dsp.window.move({ direction = "left" }),
	{ repeating = true, desc = "Move window left" }
)
hl.bind(
	mainMod .. " + CTRL + right",
	hl.dsp.window.move({ direction = "right" }),
	{ repeating = true, desc = "Move window right" }
)
hl.bind(
	mainMod .. " + CTRL + up",
	hl.dsp.window.move({ direction = "up" }),
	{ repeating = true, desc = "Move window up" }
)
hl.bind(
	mainMod .. " + CTRL + down",
	hl.dsp.window.move({ direction = "down" }),
	{ repeating = true, desc = "Move window down" }
)

-- ── Clipboard ─────────────────────────────────────────────────────────────────

hl.bind(
	mainMod .. " + CTRL + Space",
	hl.dsp.exec_cmd("uwsm-app cliphist list | rofi -dmenu | cliphist decode | wl-copy"),
	{ desc = "Open clipboard history" }
)
hl.bind(
	mainMod .. " + C",
	hl.dsp.exec_cmd("cloudyy-clipboard-open copy"),
	{ desc = "Copy (works in both terminal and GUI apps)" }
)
hl.bind(
	mainMod .. " + V",
	hl.dsp.exec_cmd("cloudyy-clipboard-open paste"),
	{ desc = "Paste (works in both terminal and GUI apps)" }
)

-- ── Workspaces ────────────────────────────────────────────────────────────────

for i = 1, 10 do
	local key = i % 10
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { desc = "Switch to workspace" })
	hl.bind(
		mainMod .. " + SHIFT + " .. key,
		hl.dsp.window.move({ workspace = i }),
		{ desc = "Move active window to workspace" }
	)
end

hl.bind(
	mainMod .. " + S",
	hl.dsp.workspace.toggle_special("magic"),
	{ desc = "Toggle scratchpad (a hidden floating workspace for quick apps)" }
)
hl.bind(
	mainMod .. " + SHIFT + S",
	hl.dsp.window.move({ workspace = "special:magic" }),
	{ desc = "Send window to scratchpad" }
)

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { desc = "Switch to next workspace" })
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { desc = "Switch to previous workspace" })

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { desc = "Move window (hold Super, drag with mouse)" })
hl.bind(
	mainMod .. " + mouse:273",
	hl.dsp.window.resize(),
	{ desc = "Resize window (hold Super, drag with right mouse button)" }
)

-- ── Misc ──────────────────────────────────────────────────────────────────────

hl.bind(
	"XF86FullScreen",
	hl.dsp.exec_cmd("hyprctl dispatch fullscreen 0"),
	{ locked = true, desc = "Toggle fullscreen" }
)
hl.bind("XF86LaunchA", hl.dsp.exec_cmd("qs ipc call spotlight command"), { locked = true, desc = "Command Center" })

hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"), { desc = "Reload Hyprland" })
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("cloudyy-clipboard-extract-text"), { desc = "Live Text Extraction" })

-- Idle scene consumes the next keypress and returns the desktop to normal.
hl.define_submap("cloudyy-idle", function()
	hl.bind("catchall", hl.dsp.exec_cmd("cloudyy-idle dismiss"))
end)

-- --- Cloud Center Additions (managed by Cloud Center) ---
-- --- End Cloud Center Additions ---
