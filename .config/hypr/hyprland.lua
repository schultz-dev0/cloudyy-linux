-- Hyprland Lua config — entry point
-- Hyprland auto-uses this file instead of hyprland.conf when it exists.
-- Modules live under ~/.config/hypr/source and ~/.config/hypr/user-configs.
-- DO NOT source hyprland.conf and hyprland.lua at the same time.

local home = os.getenv("HOME")
package.path = package.path
	.. ";"
	.. home
	.. "/.config/hypr/?.lua"
	.. ";"
	.. home
	.. "/.config/hypr/source/?.lua"
	.. ";"
	.. home
	.. "/.config/hypr/user-configs/?.lua"
	.. ";"
	.. home
	.. "/.config/hypr/.hyprlua/?.lua"

require("source.variables")
require("source.monitors")
require("source.lookandfeel")
require("source.animations")
require("source.input")
require("source.autostart")
require("source.windowrules")
require("source.bindings")
