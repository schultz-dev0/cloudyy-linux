-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

vim.o.winborder = "none"

-- (Used to force-clear StatusLine/WinBar/etc. to bg=none here, to patch gaps
-- in tokyonight's old transparent=true mode. Removed along with transparent
-- mode itself — autocmds.lua now sets transparent=false, so tokyonight
-- handles these groups' backgrounds properly on its own.)
