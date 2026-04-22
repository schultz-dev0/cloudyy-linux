-- Autocmds are automatically loaded on the VeryLazy event

local theme_watch_group = vim.api.nvim_create_augroup("ThemeAutoReload", { clear = true })
-- Watch the matugen-generated file, not the stale hand-written current_mode.lua.
local mode_file = vim.fn.expand("~/.config/matugen/generated/matugen_colors.lua")
local last_mtime = vim.fn.getftime(mode_file)

-- High-contrast palette for transparent light-mode editing.
-- Deep, saturated hues that pop against pale/warm wallpapers.
local lm = {
  text        = "#1a1a2e",
  comment     = "#4a5e6a",
  keyword     = "#5e0a7a",
  func        = "#003459",
  func_call   = "#00587a",
  type        = "#7a2000",
  string      = "#14532d",
  constant    = "#7f1d1d",
  number      = "#78350f",
  property    = "#1e3a8a",
  variable    = "#1c1c2e",
  operator    = "#374151",
  punct       = "#4b5563",
  param       = "#1e3a5f",
  special     = "#4a0060",
  namespace   = "#3b0764",
  tag         = "#003459",
  uri         = "#1d4ed8",
  cursor_line = "#e8e8f0",
  visual      = "#c7d2fe",
  search_bg   = "#fef08a",
  pmenu_bg    = "#f1f5f9",
  pmenu_sel   = "#1e3a8a",
  float_bg    = "#f0f0f8",
  error       = "#991b1b",
  warn        = "#92400e",
  info        = "#1e40af",
  hint        = "#065f46",
}

-- Called by tokyonight as the FINAL step before highlights are applied,
-- so these values are guaranteed to win over the theme's own defaults.
local function on_highlights_light(hl, _)
  local N = "NONE"

  -- ── Base UI ──────────────────────────────────────────────────────────
  hl.Normal        = { fg = lm.text,     bg = N }
  hl.NormalNC      = { fg = lm.text,     bg = N }
  hl.NormalFloat   = { fg = lm.text,     bg = N }
  hl.CursorLine    = { bg = lm.cursor_line }
  hl.LineNr        = { fg = lm.punct,    bg = N }
  hl.CursorLineNr  = { fg = lm.text,     bg = N, bold = true }
  hl.SignColumn    = { bg = N }
  hl.EndOfBuffer   = { fg = lm.punct,    bg = N }
  hl.Visual        = { bg = lm.visual }
  hl.Search        = { fg = lm.text,     bg = lm.search_bg, bold = true }
  hl.IncSearch     = { fg = lm.text,     bg = lm.search_bg, bold = true }
  hl.StatusLine    = { fg = lm.text,     bg = N }
  hl.StatusLineNC  = { fg = lm.comment,  bg = N }
  hl.WinBar        = { fg = lm.text,     bg = N }
  hl.WinBarNC      = { fg = lm.comment,  bg = N }
  hl.WinSeparator  = { fg = lm.punct,    bg = N }
  hl.Pmenu         = { fg = lm.text,     bg = lm.pmenu_bg }
  hl.PmenuSel      = { fg = "#ffffff",   bg = lm.pmenu_sel, bold = true }
  hl.PmenuSbar     = { bg = lm.cursor_line }
  hl.PmenuThumb    = { bg = lm.punct }
  hl.NonText       = { fg = lm.punct }
  hl.Whitespace    = { fg = "#c0c0c0" }
  hl.SpecialKey    = { fg = lm.punct }
  hl.Folded        = { fg = lm.text,     bg = lm.cursor_line }
  hl.FoldColumn    = { fg = lm.punct,    bg = N }
  hl.FloatBorder   = { fg = lm.punct,    bg = N }
  hl.Directory     = { fg = lm.property, bold = true }
  hl.Title         = { fg = lm.text,     bold = true }

  -- ── Legacy syntax ─────────────────────────────────────────────────────
  hl.Comment       = { fg = lm.comment,  italic = true }
  hl.Constant      = { fg = lm.constant }
  hl.String        = { fg = lm.string }
  hl.Character     = { fg = lm.string }
  hl.Number        = { fg = lm.number }
  hl.Float         = { fg = lm.number }
  hl.Boolean       = { fg = lm.constant, bold = true }
  hl.Identifier    = { fg = lm.variable }
  hl.Function      = { fg = lm.func,     bold = true }
  hl.Statement     = { fg = lm.keyword,  bold = true }
  hl.Conditional   = { fg = lm.keyword,  bold = true }
  hl.Repeat        = { fg = lm.keyword,  bold = true }
  hl.Label         = { fg = lm.keyword }
  hl.Operator      = { fg = lm.operator }
  hl.Keyword       = { fg = lm.keyword,  bold = true }
  hl.Exception     = { fg = lm.constant, bold = true }
  hl.PreProc       = { fg = lm.special }
  hl.Include       = { fg = lm.keyword,  bold = true }
  hl.Define        = { fg = lm.keyword }
  hl.Macro         = { fg = lm.special }
  hl.Type          = { fg = lm.type,     bold = true }
  hl.StorageClass  = { fg = lm.keyword,  bold = true }
  hl.Structure     = { fg = lm.type,     bold = true }
  hl.Typedef       = { fg = lm.type,     bold = true }
  hl.Special       = { fg = lm.special }
  hl.Delimiter     = { fg = lm.punct }
  hl.Underlined    = { fg = lm.uri,      underline = true }
  hl.Error         = { fg = lm.error,    bold = true }
  hl.Todo          = { fg = lm.keyword,  bold = true }

  -- ── TreeSitter — universal ────────────────────────────────────────────
  hl["@comment"]               = { fg = lm.comment,  italic = true }
  hl["@comment.documentation"] = { fg = lm.comment,  italic = true }
  hl["@keyword"]               = { fg = lm.keyword,  bold = true }
  hl["@keyword.function"]      = { fg = lm.keyword,  bold = true }
  hl["@keyword.return"]        = { fg = lm.keyword,  bold = true }
  hl["@keyword.operator"]      = { fg = lm.keyword,  bold = true }
  hl["@keyword.import"]        = { fg = lm.keyword,  bold = true }
  hl["@keyword.modifier"]      = { fg = lm.keyword,  bold = true }
  hl["@keyword.repeat"]        = { fg = lm.keyword,  bold = true }
  hl["@keyword.exception"]     = { fg = lm.constant, bold = true }
  hl["@keyword.conditional"]   = { fg = lm.keyword,  bold = true }
  hl["@keyword.coroutine"]     = { fg = lm.keyword,  bold = true }
  hl["@string"]                = { fg = lm.string }
  hl["@string.escape"]         = { fg = lm.special }
  hl["@string.special"]        = { fg = lm.special }
  hl["@string.regexp"]         = { fg = lm.special }
  hl["@string.documentation"]  = { fg = lm.comment,  italic = true }
  hl["@number"]                = { fg = lm.number }
  hl["@number.float"]          = { fg = lm.number }
  hl["@float"]                 = { fg = lm.number }
  hl["@boolean"]               = { fg = lm.constant, bold = true }
  hl["@constant"]              = { fg = lm.constant }
  hl["@constant.builtin"]      = { fg = lm.constant, bold = true }
  hl["@constant.macro"]        = { fg = lm.special }
  hl["@function"]              = { fg = lm.func,     bold = true }
  hl["@function.builtin"]      = { fg = lm.func_call, bold = true }
  hl["@function.call"]         = { fg = lm.func_call }
  hl["@function.macro"]        = { fg = lm.special }
  hl["@function.method"]       = { fg = lm.func,     bold = true }
  hl["@function.method.call"]  = { fg = lm.func_call }
  hl["@constructor"]           = { fg = lm.type,     bold = true }
  hl["@type"]                  = { fg = lm.type,     bold = true }
  hl["@type.builtin"]          = { fg = lm.type,     bold = true }
  hl["@type.definition"]       = { fg = lm.type,     bold = true }
  hl["@type.qualifier"]        = { fg = lm.keyword,  bold = true }
  hl["@variable"]              = { fg = lm.variable }
  hl["@variable.builtin"]      = { fg = lm.special,  italic = true }
  hl["@variable.parameter"]    = { fg = lm.param }
  hl["@variable.member"]       = { fg = lm.property }
  hl["@property"]              = { fg = lm.property }
  hl["@field"]                 = { fg = lm.property }
  hl["@operator"]              = { fg = lm.operator }
  hl["@punctuation.bracket"]   = { fg = lm.punct }
  hl["@punctuation.delimiter"] = { fg = lm.punct }
  hl["@punctuation.special"]   = { fg = lm.special }
  hl["@namespace"]             = { fg = lm.namespace }
  hl["@module"]                = { fg = lm.namespace }
  hl["@module.builtin"]        = { fg = lm.namespace, bold = true }
  hl["@label"]                 = { fg = lm.keyword }
  hl["@attribute"]             = { fg = lm.special }
  hl["@annotation"]            = { fg = lm.special }
  hl["@parameter"]             = { fg = lm.param }

  -- ── TreeSitter — markup / docs ────────────────────────────────────────
  hl["@markup.heading"]        = { fg = lm.text,   bold = true }
  hl["@markup.bold"]           = { fg = lm.text,   bold = true }
  hl["@markup.italic"]         = { fg = lm.text,   italic = true }
  hl["@markup.underline"]      = { underline = true }
  hl["@markup.link"]           = { fg = lm.uri,    underline = true }
  hl["@markup.link.url"]       = { fg = lm.uri,    underline = true }
  hl["@markup.raw"]            = { fg = lm.string }
  hl["@markup.list"]           = { fg = lm.keyword }

  -- ── TreeSitter — HTML / JSX ───────────────────────────────────────────
  hl["@tag"]                   = { fg = lm.tag,     bold = true }
  hl["@tag.attribute"]         = { fg = lm.property }
  hl["@tag.delimiter"]         = { fg = lm.punct }

  -- ── TreeSitter — CSS / SCSS (explicit: tokyonight sets these with ──────
  -- language-specific names that are more specific than @property etc.)  ──
  hl["@property.css"]              = { fg = lm.property }
  hl["@keyword.css"]               = { fg = lm.keyword,  bold = true }
  hl["@selector.css"]              = { fg = lm.type,     bold = true }
  hl["@number.css"]                = { fg = lm.number }
  hl["@string.css"]                = { fg = lm.string }
  hl["@string.plain.css"]          = { fg = lm.string }
  hl["@unit.css"]                  = { fg = lm.keyword }
  hl["@function.css"]              = { fg = lm.func_call }
  hl["@variable.css"]              = { fg = lm.special }
  hl["@punctuation.delimiter.css"] = { fg = lm.punct }
  hl["@punctuation.bracket.css"]   = { fg = lm.punct }
  hl["@type.css"]                  = { fg = lm.type,     bold = true }
  hl["@attribute.css"]             = { fg = lm.property }
  hl["@property.scss"]             = { fg = lm.property }
  hl["@keyword.scss"]              = { fg = lm.keyword,  bold = true }
  hl["@variable.scss"]             = { fg = lm.special }

  -- ── LSP semantic tokens (take priority over treesitter by default) ─────
  hl["@lsp.type.comment"]         = { fg = lm.comment,  italic = true }
  hl["@lsp.type.keyword"]         = { fg = lm.keyword,  bold = true }
  hl["@lsp.type.string"]          = { fg = lm.string }
  hl["@lsp.type.number"]          = { fg = lm.number }
  hl["@lsp.type.variable"]        = { fg = lm.variable }
  hl["@lsp.type.parameter"]       = { fg = lm.param }
  hl["@lsp.type.property"]        = { fg = lm.property }
  hl["@lsp.type.function"]        = { fg = lm.func,     bold = true }
  hl["@lsp.type.method"]          = { fg = lm.func,     bold = true }
  hl["@lsp.type.type"]            = { fg = lm.type,     bold = true }
  hl["@lsp.type.class"]           = { fg = lm.type,     bold = true }
  hl["@lsp.type.interface"]       = { fg = lm.type,     bold = true }
  hl["@lsp.type.enum"]            = { fg = lm.type,     bold = true }
  hl["@lsp.type.enumMember"]      = { fg = lm.constant }
  hl["@lsp.type.namespace"]       = { fg = lm.namespace }
  hl["@lsp.type.decorator"]       = { fg = lm.special }
  hl["@lsp.type.macro"]           = { fg = lm.special }
  hl["@lsp.type.builtinType"]     = { fg = lm.type,     bold = true }
  hl["@lsp.type.operator"]        = { fg = lm.operator }
  hl["@lsp.type.selfKeyword"]     = { fg = lm.special,  italic = true }

  -- ── Diagnostics ───────────────────────────────────────────────────────
  hl.DiagnosticError            = { fg = lm.error }
  hl.DiagnosticWarn             = { fg = lm.warn }
  hl.DiagnosticInfo             = { fg = lm.info }
  hl.DiagnosticHint             = { fg = lm.hint }
  hl.DiagnosticUnderlineError   = { undercurl = true, sp = lm.error }
  hl.DiagnosticUnderlineWarn    = { undercurl = true, sp = lm.warn }
  hl.DiagnosticUnderlineInfo    = { undercurl = true, sp = lm.info }
  hl.DiagnosticUnderlineHint    = { undercurl = true, sp = lm.hint }
  hl.DiagnosticVirtualTextError = { fg = lm.error, italic = true }
  hl.DiagnosticVirtualTextWarn  = { fg = lm.warn,  italic = true }
  hl.DiagnosticVirtualTextInfo  = { fg = lm.info,  italic = true }
  hl.DiagnosticVirtualTextHint  = { fg = lm.hint,  italic = true }

  -- ── Telescope ─────────────────────────────────────────────────────────
  hl.TelescopeNormal        = { fg = lm.text,     bg = N }
  hl.TelescopeBorder        = { fg = lm.punct,    bg = N }
  hl.TelescopePromptNormal  = { fg = lm.text,     bg = N }
  hl.TelescopePromptBorder  = { fg = lm.punct,    bg = N }
  hl.TelescopeResultsNormal = { fg = lm.variable, bg = N }
  hl.TelescopePreviewNormal = { fg = lm.variable, bg = N }
  hl.TelescopeMatching      = { fg = lm.keyword,  bold = true }
  hl.TelescopeSelection     = { fg = lm.text,     bg = lm.cursor_line, bold = true }

  -- ── Which-key ─────────────────────────────────────────────────────────
  hl.WhichKeyNormal    = { fg = lm.text,     bg = N }
  hl.WhichKeyFloat     = { fg = lm.text,     bg = N }
  hl.WhichKeyBorder    = { fg = lm.punct,    bg = N }
  hl.WhichKey          = { fg = lm.keyword,  bold = true }
  hl.WhichKeyGroup     = { fg = lm.property, bold = true }
  hl.WhichKeyDesc      = { fg = lm.text }
  hl.WhichKeySeparator = { fg = lm.punct }
  hl.WhichKeyValue     = { fg = lm.comment }
  hl.WhichKeyTitle     = { fg = lm.text,     bold = true }

  -- ── Snacks (dashboard + UI) ───────────────────────────────────────────
  hl.SnacksDashboardNormal  = { fg = lm.text,     bg = N }
  hl.SnacksDashboardHeader  = { fg = lm.property, bold = true }
  hl.SnacksDashboardFooter  = { fg = lm.comment,  italic = true }
  hl.SnacksDashboardTitle   = { fg = lm.text,     bold = true }
  hl.SnacksDashboardDesc    = { fg = lm.text }
  hl.SnacksDashboardKey     = { fg = lm.keyword,  bold = true }
  hl.SnacksDashboardIcon    = { fg = lm.property }
  hl.SnacksDashboardDir     = { fg = lm.comment }
  hl.SnacksDashboardFile    = { fg = lm.text }
  hl.SnacksDashboardSpecial = { fg = lm.special }
  hl.SnacksNormal           = { fg = lm.text,     bg = N }
  hl.SnacksBorder           = { fg = lm.punct,    bg = N }

  -- ── Noice (cmdline / notification floats) ────────────────────────────
  hl.NoicePopup              = { fg = lm.text, bg = lm.float_bg }
  hl.NoicePopupBorder        = { fg = lm.punct, bg = N }
  hl.NoiceCmdlinePopup       = { fg = lm.text, bg = lm.float_bg }
  hl.NoiceCmdlinePopupBorder = { fg = lm.punct }
  hl.NoiceCmdlineIcon        = { fg = lm.keyword }
  hl.NoiceConfirm            = { fg = lm.text, bg = lm.float_bg }
  hl.NoiceConfirmBorder      = { fg = lm.punct }
  hl.NoiceMini               = { fg = lm.text, bg = lm.float_bg }

  -- ── Lazy / Mason ──────────────────────────────────────────────────────
  hl.LazyNormal       = { fg = lm.text,    bg = N }
  hl.LazyTitle        = { fg = lm.text,    bold = true }
  hl.LazyH1           = { fg = "#ffffff",  bg = lm.property, bold = true }
  hl.LazyButton       = { fg = lm.text,    bg = lm.cursor_line }
  hl.LazyButtonActive = { fg = "#ffffff",  bg = lm.property, bold = true }
  hl.LazySpecial      = { fg = lm.special }
  hl.LazyDir          = { fg = lm.property, bold = true }
  hl.LazyUrl          = { fg = lm.uri,     underline = true }
  hl.LazyCommit       = { fg = lm.number }
  hl.LazyProp         = { fg = lm.comment }
  hl.LazyReasonStart  = { fg = lm.hint }
  hl.LazyReasonPlugin = { fg = lm.warn }
  hl.MasonNormal      = { fg = lm.text,    bg = N }
  hl.MasonHeader      = { fg = "#ffffff",  bg = lm.property, bold = true }
end

local function apply_mode_and_theme(notify)
  -- dofile executes the matugen-generated file directly (it's outside the lua path).
  -- The file contains: vim.opt.background = "light"|"dark"
  pcall(dofile, mode_file)

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
      -- on_highlights is the last step before highlights are applied —
      -- guaranteed to win over tokyonight's own defaults.
      on_highlights = is_light and on_highlights_light or nil,
    })
  end

  vim.cmd("colorscheme tokyonight")

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

-- Apply immediately — autocmds.lua loads on VeryLazy, which fires after VimEnter,
-- so all plugins (including tokyonight) are guaranteed to be loaded here.
apply_mode_and_theme(false)

-- Pick up theme changes made outside Neovim (matugen/theme_controller).
vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "BufEnter" }, {
  group = theme_watch_group,
  callback = function()
    maybe_reload_from_mode_file(true)
  end,
})

-- Exposed for reload_theme.sh: nvim --server <sock> --remote-expr "execute('ThemeReload')"
vim.api.nvim_create_user_command("ThemeReload", function()
  apply_mode_and_theme(true)
end, {})
