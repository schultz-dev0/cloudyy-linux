return {
  -- If you use Tokyonight
  {
    "folke/tokyonight.nvim",
    lazy = false,
    opts = {
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },

  -- If you use Catppuccin
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      transparent_background = true,
      integrations = {
        telescope = { enabled = true, style = "nvchad" }, -- Keeps telescope clean
      },
    },
  },
}
