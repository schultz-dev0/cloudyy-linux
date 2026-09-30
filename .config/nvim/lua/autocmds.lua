-- Loaded from init.lua via `require "autocmds"`.
--
-- Cloudyy curated-theme integration: reads the active theme's nvim asset
-- (state_home/cloudyy/current/theme/applications/nvim.lua), applies its
-- highlight overrides on top of NvChad's base46 theme, and re-applies them
-- whenever the active theme changes on disk.

local state_home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
local theme_file = state_home .. "/cloudyy/current/theme/applications/nvim.lua"
local theme_watch_group = vim.api.nvim_create_augroup("ThemeAutoReload", { clear = true })
local last_mtime = -1

-- Syntax colors are not taken from the curated theme: a theme's UI tokens
-- make poor syntax colors (low contrast, too few hues). base46 supplies them
-- instead, one tuned scheme per mode; the theme's nvim.lua only paints UI.
local syntax_themes = {
  dark = require("nvconfig").base46.theme, -- chadrc's pick
  light = "one_light",
}
-- Both schemes' comment colors vanish on the curated backgrounds (~2:1).
-- One gray per mode, ~4:1+ on every theme's background, still dimmer than text.
local comment_colors = { dark = "#8b93a1", light = "#6e7178" }

local function resolved_highlight(spec, palette)
  local resolved = {}
  for key, value in pairs(spec) do
    if (key == "fg" or key == "bg" or key == "sp") and palette[value] then
      resolved[key] = palette[value]
    else
      resolved[key] = value
    end
  end
  return resolved
end

local function apply_curated_theme(notify)
  local ok, theme = pcall(dofile, theme_file)
  if not ok or type(theme) ~= "table" or type(theme.palette) ~= "table"
      or type(theme.highlights) ~= "table" or (theme.mode ~= "dark" and theme.mode ~= "light") then
    if notify then
      vim.notify("Active Cloudyy theme is unavailable or invalid", vim.log.levels.ERROR)
    end
    return false
  end

  vim.opt.background = theme.mode
  -- init.lua already loaded whatever base46 last compiled, which may be the
  -- other mode's scheme; the marker records which one that was, so the
  -- cache is only recompiled on an actual light/dark flip.
  require("nvconfig").base46.theme = syntax_themes[theme.mode]
  local marker = vim.g.base46_cache .. "cloudyy_syntax_theme"
  local compiled = vim.fn.filereadable(marker) == 1 and vim.fn.readfile(marker, "", 1)[1] or ""
  if compiled ~= syntax_themes[theme.mode] then
    if pcall(function() require("base46").load_all_highlights() end) then
      vim.fn.writefile({ syntax_themes[theme.mode] }, marker)
    end
  end
  for group, spec in pairs(theme.highlights) do
    if type(group) == "string" and type(spec) == "table" then
      vim.api.nvim_set_hl(0, group, resolved_highlight(spec, theme.palette))
    end
  end
  for _, group in ipairs { "Comment", "@comment" } do
    vim.api.nvim_set_hl(0, group, { fg = comment_colors[theme.mode] })
  end
  last_mtime = vim.fn.getftime(theme_file)
  if notify then
    vim.notify("Theme reloaded: " .. (theme.name or "Cloudyy"), vim.log.levels.INFO)
  end
  return true
end

local function maybe_reload_curated_theme()
  local mtime = vim.fn.getftime(theme_file)
  if mtime > 0 and mtime ~= last_mtime then
    apply_curated_theme(true)
  end
end

apply_curated_theme(false)

-- NvChad lazy-loads base46 caches from plugin configs (e.g. telescope, cmp on
-- first use), which would stomp the UI groups above.
vim.api.nvim_create_autocmd("User", {
  group = theme_watch_group,
  pattern = "LazyLoad",
  callback = function() apply_curated_theme(false) end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "BufEnter" }, {
  group = theme_watch_group,
  callback = maybe_reload_curated_theme,
})

vim.api.nvim_create_user_command("ThemeReload", function()
  apply_curated_theme(true)
end, {})

-- bindings.lua is hand-formatted (one hl.bind() arg per line for readability).
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*/hypr/source/bindings.lua",
  callback = function(args)
    vim.b[args.buf].autoformat = false
  end,
})
