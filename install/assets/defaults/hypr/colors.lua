-- Hyprland theme tokens from matugen (generated hyprcolors.conf).
-- Source: ~/.config/matugen/generated/hyprcolors.conf

local M = {}

local path = os.getenv("HOME") .. "/.config/matugen/generated/hyprcolors.conf"
local f = io.open(path, "r")
if f then
	for line in f:lines() do
		local name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
		if name and value and value ~= "" then
			M[name] = value
		end
	end
	f:close()
end

M.primary = M.primary or "rgba(88c0d0ff)"
M.inverse_on_surface = M.inverse_on_surface or "rgba(595959aa)"

return M
