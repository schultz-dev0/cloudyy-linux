-- Hyprland Lua config — entry point
-- Hyprland auto-uses this file instead of hyprland.conf when it exists.
-- Every module lives as a single ~/.config/hypr/<name>.lua file — there is
-- no more source/ vs. user-configs/ split. Cloud Center edits modules in
-- place; it never rewrites this file's require lines.
-- DO NOT source hyprland.conf and hyprland.lua at the same time.

local home = os.getenv("HOME")
package.path = package.path
	.. ";"
	.. home
	.. "/.config/hypr/?.lua"
	.. ";"
	.. home
	.. "/.config/hypr/.hyprlua/?.lua"

require("variables")
require("monitors")
require("lookandfeel")
require("animations")
require("input")
require("autostart")
require("windowrules")
require("cursor")
require("bindings")
