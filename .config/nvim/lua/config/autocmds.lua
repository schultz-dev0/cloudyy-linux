-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--

-- Watch the matugen_colors file for changes
local matugen_path = vim.fn.stdpath("config") .. "/lua/matugen_colors.lua"

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "matugen_colors.lua",
  callback = function()
    -- Clear the Lua cache so it picks up the new file content
    package.loaded["matugen_colors"] = nil
    -- Re-trigger the colorscheme to apply our overrides
    vim.cmd("colorscheme " .. (vim.g.colors_name or "tokyonight"))
    vim.notify("Matugen colors updated!", vim.log.levels.INFO)
  end,
})

-- LazyVim Theme Auto-Reload Configuration
-- Add this to your ~/.config/nvim/lua/config/autocmds.lua

-- Watch for theme change notifications
local theme_watch_group = vim.api.nvim_create_augroup("ThemeAutoReload", { clear = true })

-- Method 1: Watch for signal (SIGUSR1)
vim.api.nvim_create_autocmd("Signal", {
  group = theme_watch_group,
  pattern = "SIGUSR1",
  callback = function()
    -- Reload colorscheme
    vim.cmd("colorscheme " .. vim.g.colors_name)
    vim.notify("Theme reloaded via signal", vim.log.levels.INFO)
  end,
})

-- Method 2: Watch for file changes
local theme_notify_file = vim.fn.expand("~/.cache/theme_notify/colorscheme_changed")

vim.api.nvim_create_autocmd({ "BufWritePost", "FileChangedShellPost" }, {
  group = theme_watch_group,
  pattern = theme_notify_file,
  callback = function()
    -- Small delay to ensure matugen has finished
    vim.defer_fn(function()
      -- Source any theme-specific config
      local theme_config = vim.fn.expand("~/.config/nvim/lua/plugins/colorscheme.lua")
      if vim.fn.filereadable(theme_config) == 1 then
        vim.cmd("source " .. theme_config)
      end

      -- Reload colorscheme
      if vim.g.colors_name then
        vim.cmd("colorscheme " .. vim.g.colors_name)
      end

      vim.notify("Theme reloaded from matugen", vim.log.levels.INFO)
    end, 100)
  end,
})

-- Method 3: Poll for changes (fallback)
-- Only enable if signals don't work
-- local timer = vim.loop.new_timer()
-- timer:start(0, 5000, vim.schedule_wrap(function()
--   if vim.fn.getftime(theme_notify_file) > (vim.g.last_theme_check or 0) then
--     vim.g.last_theme_check = vim.fn.getftime(theme_notify_file)
--     vim.cmd("colorscheme " .. vim.g.colors_name)
--   end
-- end))
