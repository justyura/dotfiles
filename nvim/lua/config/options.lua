vim.opt.clipboard = "unnamedplus"
vim.opt.scrolloff = 8
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- 折叠：用 treesitter 的语法树，所以 za/zc 折的是真正的函数体而不是缩进块。
-- foldlevel 拉到 99 = 打开文件时全部展开，只在你主动 za 时才折。
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldtext = ""
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99

vim.cmd [[hi @function.builtin guifg=yellow]]
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.hl.on_yank()
  end,
})
