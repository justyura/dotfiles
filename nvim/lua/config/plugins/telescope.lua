return {
  'nvim-telescope/telescope.nvim',
  version = '0.2.*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
  },
  keys = {
    { '<leader>ff', '<cmd>Telescope find_files<cr>',    desc = 'Telescope find files' },
    { '<leader>fg', '<cmd>Telescope live_grep<cr>',     desc = 'Telescope live grep' },
    { '<leader>fb', '<cmd>Telescope buffers<cr>',       desc = 'Telescope buffers' },
    { '<leader>fh', '<cmd>Telescope help_tags<cr>',     desc = 'Telescope help tags' },
    { '<leader>fo', '<cmd>Telescope oldfiles<cr>',      desc = 'Recent files' },
    { '<leader>fe', '<cmd>Telescope diagnostics<cr>',   desc = 'Diagnostics' },
    { '<leader>fc', '<cmd>Telescope git_commits<cr>',   desc = 'Git commits' },
    { '<leader>ft', '<cmd>Telescope todo-comments<cr>', desc = 'Telescope todo-comments' },
    {
      '<space>en',
      function()
        require('telescope.builtin').find_files { cwd = vim.fn.stdpath('config') }
      end,
      desc = 'Neovim config files'
    },
    {
      '<space>fd',
      function()
        local current_file = vim.fn.expand('%:p')
        local current_dir = vim.fn.expand('%:p:h')
        if current_file == '' then current_dir = vim.fn.getcwd() end
        local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(current_dir) .. ' rev-parse --show-toplevel')
            [1]
        local opts = {}
        if vim.v.shell_error == 0 then
          opts.cwd = git_root
        else
          opts.cwd = current_dir
        end
        require('telescope.builtin').find_files(opts)
      end,
      desc = 'Find files from git root'
    },
  },
  opts = {
    defaults = {
      layout_strategy = 'horizontal',
      file_ignore_patterns = { '.git/' },
      history = { limit = 100 },
    },
    pickers = {
      find_files = {
        theme = "ivy",
      },
      help_tags = {
        theme = "dropdown",
      },
      oldfiles = { only_cwd = true },
      diagnostics = { severity = 'error' },
    },
  },
}
