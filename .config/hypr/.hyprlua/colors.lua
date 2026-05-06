-- Parses ~/.config/matugen/generated/hyprcolors.conf and exposes color tokens
-- as a plain table.  require("colors") returns the table.
-- Falls back to safe defaults if the file hasn't been generated yet.

local M = {}

local path = os.getenv("HOME") .. "/.config/matugen/generated/hyprcolors.conf"
local f    = io.open(path, "r")
if f then
    for line in f:lines() do
        local name, value = line:match("^%$(%w+)%s*=%s*(.-)%s*$")
        if name and value and value ~= "" then
            M[name] = value
        end
    end
    f:close()
end

-- Fallbacks
M.primary           = M.primary           or "rgba(88c0d0ff)"
M.inverse_on_surface = M.inverse_on_surface or "rgba(595959aa)"

return M
