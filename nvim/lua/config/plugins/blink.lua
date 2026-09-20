return {
  'saghen/blink.cmp',
  dependencies = { 'rafamadriz/friendly-snippets' },
  version = '1.*',

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
    keymap = { preset = 'super-tab' },
    signature = { enabled = true },

    appearance = {
      -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = 'mono'
    },

    completion = {
      documentation = { auto_show = true },
      accept = {
        auto_brackets = { enabled = true },
      }
    },

    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
      per_filetype = {
        markdown = { 'snippets' },
      },
    },

    fuzzy = { implementation = "prefer_rust_with_warning" },

    enabled = function()
      return not vim.tbl_contains({ "text" }, vim.bo.filetype)
    end

  },
  opts_extend = { "sources.default" }
}
