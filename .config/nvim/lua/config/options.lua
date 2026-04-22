-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

vim.o.winborder = "none"

-- tokyonight transparent=true covers Normal/NormalNC/NormalFloat/SignColumn/EndOfBuffer.
-- These extra groups are not included in its transparent mode, so clear them here.
-- Light mode gets these set properly via on_highlights_light in autocmds.lua.
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    if vim.o.background ~= "light" then
      for _, g in ipairs({
        "StatusLine", "StatusLineNC", "WinBar", "WinBarNC", "WinSeparator",
      }) do
        vim.api.nvim_set_hl(0, g, { bg = "none", ctermbg = "none" })
      end
    end
  end,
})
