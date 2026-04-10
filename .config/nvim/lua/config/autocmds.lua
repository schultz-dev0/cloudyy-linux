-- Autocmds are automatically loaded on the VeryLazy event

local theme_watch_group = vim.api.nvim_create_augroup("ThemeAutoReload", { clear = true })
local mode_file = vim.fn.stdpath("config") .. "/lua/current_mode.lua"

local last_mtime = vim.fn.getftime(mode_file)

local function apply_mode_and_theme(notify)
  package.loaded["current_mode"] = nil
  pcall(require, "current_mode")

  local is_light = vim.o.background == "light"
  local ok, tokyonight = pcall(require, "tokyonight")
  if ok then
    tokyonight.setup({
      style = is_light and "day" or "moon",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    })
  end

  vim.cmd("colorscheme " .. (vim.g.colors_name or "tokyonight"))

  if notify then
    vim.notify("Theme reloaded from Matugen mode", vim.log.levels.INFO)
  end
end

local function maybe_reload_from_mode_file(notify)
  local mtime = vim.fn.getftime(mode_file)
  if mtime <= 0 then
    return
  end

  if mtime ~= last_mtime then
    last_mtime = mtime
    apply_mode_and_theme(notify)
  end
end

-- On startup, apply current mode and proper style once.
vim.api.nvim_create_autocmd("VimEnter", {
  group = theme_watch_group,
  callback = function()
    apply_mode_and_theme(false)
  end,
})

-- Pick up theme changes made outside Neovim (matugen/theme_controller).
vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "BufEnter" }, {
  group = theme_watch_group,
  callback = function()
    maybe_reload_from_mode_file(true)
  end,
})
