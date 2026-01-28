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
