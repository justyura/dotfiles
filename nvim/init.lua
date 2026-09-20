vim.diagnostic.config({ virtual_text = true })

require("config.lazy")
require("config.keymaps")
require("config.options")

vim.lsp.enable('lua_ls')
vim.lsp.enable('gopls')
vim.lsp.enable('html')
