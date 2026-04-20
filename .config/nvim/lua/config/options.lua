-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
-- Load Matugen-generated mode (sets vim.opt.background to light/dark) when available.
pcall(function()
  local matugen_path = vim.fn.expand("~/.config/matugen/generated/matugen_colors.lua")
  if vim.loop.fs_stat(matugen_path) then
    dofile(matugen_path)
  end
end)

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
      -- Deeper, high-contrast colors for light mode readability
      vim.api.nvim_set_hl(0, "Normal", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "Comment", { fg = "#2a3a4a", italic = true })
      vim.api.nvim_set_hl(0, "Identifier", { fg = "#002060" })
      vim.api.nvim_set_hl(0, "Function", { fg = "#003040", bold = true })
      vim.api.nvim_set_hl(0, "Statement", { fg = "#400080", bold = true })
      vim.api.nvim_set_hl(0, "Keyword", { fg = "#400080", bold = true })
      vim.api.nvim_set_hl(0, "Type", { fg = "#603000", bold = true })
      vim.api.nvim_set_hl(0, "String", { fg = "#004020" })
      vim.api.nvim_set_hl(0, "Constant", { fg = "#802000" })
      vim.api.nvim_set_hl(0, "PreProc", { fg = "#600040" })
      vim.api.nvim_set_hl(0, "Special", { fg = "#402080" })
      vim.api.nvim_set_hl(0, "Number", { fg = "#802000" })
      vim.api.nvim_set_hl(0, "Title", { fg = "#000000", bold = true })
      vim.api.nvim_set_hl(0, "Directory", { fg = "#002060", bold = true })
      vim.api.nvim_set_hl(0, "NonText", { fg = "#505050" })
      vim.api.nvim_set_hl(0, "Whitespace", { fg = "#a0a0a0" })
      vim.api.nvim_set_hl(0, "SpecialKey", { fg = "#505050" })
      vim.api.nvim_set_hl(0, "Folded", { fg = "#000000", bg = "#d0d0d0" })

      -- UI Elements
      vim.api.nvim_set_hl(0, "LineNr", { fg = "#101010", bg = "none" })
      vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#000000", bg = "none", bold = true })
      vim.api.nvim_set_hl(0, "StatusLine", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "StatusLineNC", { fg = "#202020", bg = "none" })
      vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "Visual", { bg = "#c0c0c0" })
      vim.api.nvim_set_hl(0, "Search", { bg = "#ffff00", fg = "#000000", bold = true })
      vim.api.nvim_set_hl(0, "CursorLine", { bg = "#e0e0e0" })
      vim.api.nvim_set_hl(0, "Pmenu", { fg = "#000000", bg = "#f0f0f0" })
      vim.api.nvim_set_hl(0, "PmenuSel", { fg = "#ffffff", bg = "#002060" })

      -- Plugin Specific (Lazy UI seen in screenshot)
      vim.api.nvim_set_hl(0, "LazyNormal", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "LazyTitle", { fg = "#000000", bold = true })
      vim.api.nvim_set_hl(0, "LazyH1", { fg = "#ffffff", bg = "#000000", bold = true })
      vim.api.nvim_set_hl(0, "LazyButton", { fg = "#000000", bg = "#d0d0d0" })
      vim.api.nvim_set_hl(0, "LazyButtonActive", { fg = "#ffffff", bg = "#000000", bold = true })
      vim.api.nvim_set_hl(0, "LazySpecial", { fg = "#402080" })
      vim.api.nvim_set_hl(0, "LazyDir", { fg = "#002060", bold = true })
      vim.api.nvim_set_hl(0, "LazyUrl", { fg = "#004080", underline = true })
      vim.api.nvim_set_hl(0, "LazyCommit", { fg = "#802000" })
      vim.api.nvim_set_hl(0, "LazyNoNames", { fg = "#400080" })
      vim.api.nvim_set_hl(0, "LazyProp", { fg = "#505050" })
      vim.api.nvim_set_hl(0, "LazyReasonStart", { fg = "#006030" })
      vim.api.nvim_set_hl(0, "LazyReasonPlugin", { fg = "#603000" })

      -- Mason / Others
      vim.api.nvim_set_hl(0, "MasonNormal", { fg = "#000000", bg = "none" })
      vim.api.nvim_set_hl(0, "MasonHeader", { fg = "#ffffff", bg = "#000000", bold = true })

      -- Diagnostics
      vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#a00000" })
      vim.api.nvim_set_hl(0, "DiagnosticWarn", { fg = "#804000" })
      vim.api.nvim_set_hl(0, "DiagnosticInfo", { fg = "#004080" })
      vim.api.nvim_set_hl(0, "DiagnosticHint", { fg = "#006030" })
    end
  end,
})
