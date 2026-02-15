vim.keymap.set("n", "<space><space>x", function ()
    vim.cmd("source %")
    print("config reloaded!")
end)
vim.keymap.set("n", "<space>pv", ":Vex<CR>")
vim.keymap.set("n", "Y", "mmggyG`m")
-- 缩进与选中优化
vim.keymap.set("v", ">", ">gv")
vim.keymap.set("v", "<", "<gv")
vim.keymap.set("n", ">", "V>")
vim.keymap.set("n", "<", "V<")


-- Move lines up and down in visual mode (ThePrimeagen style)
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

vim.keymap.set("n", "<leader>z", "<C-w>|<C-w>_", { desc = "Zoom window" })
vim.keymap.set("n", "<leader>Z", "<C-w>=", { desc = "Restore windows" })
