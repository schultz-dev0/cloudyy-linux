return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
      on_highlights = function(hl, c)
        -- Keep the transparency forced
        hl.Normal = { bg = "none" }
        hl.NormalNC = { bg = "none" }
        hl.CursorLine = { bg = "none" }

        -- Load colors, but fail silently to avoid the red box
        local status, m = pcall(require, "colors")
        if status and m then
          hl.LineNr = { fg = m.accent }
          hl.CursorLineNr = { fg = m.primary, bold = true }
          hl.Visual = { bg = m.selection }
          hl.TelescopeBorder = { fg = m.primary }
        end
      end,
    },
    -- Removed the manual 'config' function to let LazyVim handle the load quietly
  },
}
