if vim.fn.has("nvim-0.12") == 0 then
	vim.api.nvim_echo({ { "This configuration requires Neovim 0.12 or newer.", "ErrorMsg" } }, true, {})
	return
end

vim.diagnostic.config({ virtual_text = true })

require("config.lazy")
require("config.keymaps")
require("config.options")

vim.lsp.enable('lua_ls')
vim.lsp.enable('gopls')
vim.lsp.enable('html')
