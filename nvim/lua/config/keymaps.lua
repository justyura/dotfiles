vim.keymap.set("n", "<space><space>x", function()
  vim.cmd("source %")
  print("config reloaded!")
end)
vim.keymap.set("n", "<space>pv", ":Vex<CR>")
vim.keymap.set("n", "Y", "mmggyG`m")

vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("n", ">", "V>")
vim.keymap.set("n", "<", "V<")

-- Move lines up and down in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })

-- ]d / [d 是 0.11+ 内置的「跳下一个诊断」，不分级别。
-- 这两个只在 ERROR 之间跳，warning/hint 直接跳过。
vim.keymap.set("n", "]e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Next error" })
vim.keymap.set("n", "[e", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Prev error" })
