vim.keymap.set('n', 'df', 'yyGpo', { buffer = true })
vim.keymap.set('n', 'da', '/# Answer<CR>O- ', { buffer = true })

-- v-prefix shortcuts
vim.keymap.set("i", "vj", "<Esc>o<space><space><space><C-k>-v<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("n", "vj", "<Esc>o<space><space><space><C-k>-v<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vk", "<Esc>o<space><space><space><C-k>!-<Esc>o<BS>", { buffer = 0 })
vim.keymap.set("i", "vl", "<C-k>-><space>", { buffer = 0 })
vim.keymap.set("i", "vh", "<C-k><-", { buffer = 0 })
vim.keymap.set("i", "v*", "<C-k>2*<space>", { buffer = 0 })
vim.keymap.set("i", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`ma", { buffer = 0 })
vim.keymap.set("v", "vv", "<Esc>hea<Esc>byiwi★<Esc>emmGo<CR>★ <Esc>p<Esc>`m", { buffer = 0 })
vim.keymap.set("n", "<leader>d", "I~~<Esc>A~~<Esc>", { buffer = 0 })

-- 渲染开关：写的时候关掉看原始语法，读的时候打开
vim.keymap.set("n", "<leader>m", "<Cmd>RenderMarkdown toggle<CR>",
  { buffer = 0, desc = "Toggle markdown render" })
