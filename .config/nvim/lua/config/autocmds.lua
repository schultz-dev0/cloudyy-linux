-- Autocmds are automatically loaded on the VeryLazy event.

local state_home = vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")
local theme_file = state_home .. "/cloudyy/current/theme/applications/nvim.lua"
local theme_watch_group = vim.api.nvim_create_augroup("ThemeAutoReload", { clear = true })
local last_mtime = -1

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
  pcall(vim.cmd.colorscheme, "tokyonight")
  for group, spec in pairs(theme.highlights) do
    if type(group) == "string" and type(spec) == "table" then
      vim.api.nvim_set_hl(0, group, resolved_highlight(spec, theme.palette))
    end
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
