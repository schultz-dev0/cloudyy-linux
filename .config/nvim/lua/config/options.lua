-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
-- Load Matugen-generated mode (sets vim.opt.background to light/dark) when available.
-- vim.opt.clipboard = "unnamedplus"
pcall(require, "current_mode")

-- Remove default float/window borders for a cleaner look.
vim.o.winborder = "none"

-- Global Transparency (Omarchy style)
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    vim.api.nvim_set_hl(0, "FloatBorder", { fg = "NONE", bg = "NONE" })
    vim.api.nvim_set_hl(0, "WinSeparator", { fg = "NONE", bg = "NONE" })

    local hl_groups = {
      "Normal",
      "NormalNC",
      "NormalFloat",
      "FloatBorder",
      "SignColumn",
      "LineNr",
      "CursorLineNr",
      "StatusLine",
      "StatusLineNC",
      "WinBar",
      "WinBarNC",
      "EndOfBuffer",
      "CursorLine",
    }
    for _, group in ipairs(hl_groups) do
      vim.api.nvim_set_hl(0, group, { bg = "none", ctermbg = "none" })
    end

    -- Light mode needs stronger token contrast when background is transparent.
    if vim.o.background == "light" then
      vim.api.nvim_set_hl(0, "Normal", { fg = "#1f2329", bg = "none" })
      vim.api.nvim_set_hl(0, "Comment", { fg = "#5f6a7a", italic = true })
      vim.api.nvim_set_hl(0, "Identifier", { fg = "#0b4f8a" })
      vim.api.nvim_set_hl(0, "Function", { fg = "#005a9c" })
      vim.api.nvim_set_hl(0, "Statement", { fg = "#7a3e9d", bold = true })
      vim.api.nvim_set_hl(0, "Keyword", { fg = "#7a3e9d", bold = true })
      vim.api.nvim_set_hl(0, "Type", { fg = "#8a4b00" })
      vim.api.nvim_set_hl(0, "String", { fg = "#0f7b4b" })
      vim.api.nvim_set_hl(0, "Constant", { fg = "#b24700" })
    end
  end,
})
