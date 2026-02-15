-- after/ftplugin/text.lua

-- Move lines
vim.keymap.set("n", "J", ":m .+1<CR>==", { buffer = 0 })
vim.keymap.set("n", "K", ":m .-2<CR>==", { buffer = 0 })

-- Auto Save
vim.api.nvim_create_autocmd('InsertLeave', {
  buffer = 0,
  callback = function()
    vim.cmd('silent! write')
  end
})

-- v-prefix shortcuts
vim.keymap.set("i", "vj", "<Esc>o<space><space><space><C-k>-v<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vk", "<Esc>o<space><space><space><C-k>!-<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vl", "<C-k>-><space>", { buffer = 0 })
vim.keymap.set("i", "vh", "<C-k><-", { buffer = 0 })
vim.keymap.set("i", "v*", "<C-k>2*<space>", { buffer = 0 })
vim.keymap.set("i", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`ma", { buffer = 0 })
vim.keymap.set("v", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`m", { buffer = 0 })
