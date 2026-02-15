return {
  {
    'nvim-telescope/telescope.nvim',
    tag = '0.1.8',
    dependencies = {
      'nvim-lua/plenary.nvim',
      { 'nvim-telescope/telescope-fzf-native.nvim', build = 'make'}
    },
    config = function ()
      local builtin = require('telescope.builtin')
      -- 智能查找文件:基于当前文件所在目录查找项目根(遵守 gitignore)
      vim.keymap.set("n", "<space>fd", function()
	local opts = {}
	-- 获取当前 buffer 的目录
	local current_file = vim.fn.expand('%:p')
	local current_dir = vim.fn.expand('%:p:h')
	-- 如果没有打开文件,使用 cwd
	if current_file == '' then
	  current_dir = vim.fn.getcwd()
	end

	-- 从当前文件目录向上查找 git 根目录
	local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(current_dir) .. ' rev-parse --show-toplevel')[1]

	if vim.v.shell_error == 0 then
	  opts.cwd = git_root
	else
	  -- 不在 git 仓库,使用当前文件所在目录
	  opts.cwd = current_dir
	end

	builtin.find_files(opts)
      end)

      -- 查找所有文件(包括 gitignore 和隐藏文件)
      vim.keymap.set("n", "<space>fD", function()
	local opts = {
	  hidden = true,
	  no_ignore = true,
	  no_ignore_parent = true,
	}

	local current_file = vim.fn.expand('%:p')
	local current_dir = vim.fn.expand('%:p:h')

	if current_file == '' then
	  current_dir = vim.fn.getcwd()
	end

	local git_root = vim.fn.systemlist('git -C ' .. vim.fn.shellescape(current_dir) .. ' rev-parse --show-toplevel')[1]

	if vim.v.shell_error == 0 then
	  opts.cwd = git_root
	else
	  opts.cwd = current_dir
	end

	builtin.find_files(opts)
      end)

      -- LSP 引用查找
      vim.keymap.set("n", "<space>gr", builtin.lsp_references)

      -- LSP 符号查找(解决显示不全问题)
      vim.keymap.set("n", "<space>fs", function()
	builtin.lsp_document_symbols({
	  layout_strategy = 'vertical',
	  layout_config = {
	    width = 0.9,
	    height = 0.9,
	  },
	})
      end)

      -- Telescope 全局配置
      require('telescope').setup({
	defaults = {
	  layout_config = {
	    horizontal = {
	      width = 0.9,
	      preview_width = 0.6,
	    },
	  },
	},
	pickers = {
	  lsp_document_symbols = {
	    symbol_width = 50,
	  },
	},
	extensions = {
	  fzf = {
	    fuzzy = true,
	    override_generic_sorter = true,
	    override_file_sorter = true,
	    case_mode = "smart_case",
	  }
	}
      })

      -- 加载 fzf 扩展
      require('telescope').load_extension('fzf')
    end
  }
}
