-- Hyprland Lua config — entry point
-- Hyprland auto-uses this file instead of hyprland.conf when it exists.
-- Modules live in ~/.config/hypr/.hyprlua/
-- DO NOT source hyprland.conf and hyprland.lua at the same time.

local hyprlua = os.getenv("HOME") .. "/.config/hypr/.hyprlua"
package.path  = package.path .. ";" .. hyprlua .. "/?.lua"

require("env")
require("monitors")
require("lookandfeel")
require("animations")
require("input")
require("autostart")
require("windowrules")
require("bindings")
