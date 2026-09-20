return {
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  lazy = false,
  build = ':TSUpdate',
  config = function()
    local ts = require('nvim-treesitter')

    ts.setup {
      install_dir = vim.fn.stdpath('data') .. '/site',
    }

    ts.install {
      -- Neovim 0.12 already includes Lua, Vim, Vimdoc, Markdown, and
      -- Markdown Inline parsers. Keep only languages used by this setup.
      'bash',
      'json', 'yaml', 'toml',
      'tmux',
      'go', 'gomod', 'gosum', 'gowork',
    }

    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
      end,
    })

    vim.api.nvim_create_autocmd('FileType', {
      callback = function(args)
        if pcall(vim.treesitter.language.get_lang, vim.bo[args.buf].filetype) then
          vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end,
    })
  end,
}
