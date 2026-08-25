-- Curated Cloudyy color tokens. Theme packages own values only; Hyprland
-- behavior remains in the Lua configuration that consumes this module.

local M = {
	background = "rgb(2e3440)",
	surface = "rgb(3b4252)",
	surface_raised = "rgb(434c5e)",
	surface_overlay = "rgb(4c566a)",
	text = "rgb(eceff4)",
	text_muted = "rgb(e5e9f0)",
	accent = "rgb(88c0d0)",
	accent_muted = "rgb(5e81ac)",
	accent_alt = "rgb(8fbcbb)",
	on_accent = "rgb(2e3440)",
	border = "rgb(4c566a)",
	selection = "rgb(434c5e)",
	success = "rgb(a3be8c)",
	warning = "rgb(ebcb8b)",
	error = "rgb(bf616a)",
	info = "rgb(81a1c1)",
	shadow = "rgb(2e3440)",
}

local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
	local home = os.getenv("HOME") or ""
	config_home = home .. "/.config"
end

local path = config_home .. "/hypr/cloudyy-theme.conf"
local f = io.open(path, "r")
if f then
	for line in f:lines() do
		local name, value = line:match("^%$([%w_]+)%s*=%s*(rgb%(%x%x%x%x%x%x%))%s*$")
		if name and M[name] ~= nil then
			M[name] = value
		end
	end
	f:close()
end

return M
