return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true, -- Enable transparency by default
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },

  -- If you prefer Catppuccin, uncomment this and comment out tokyonight above
  -- {
  --   "catppuccin/nvim",
  --   lazy = false,
  --   name = "catppuccin",
  --   opts = {
  --     transparent_background = true,
  --   },
  -- },
}
