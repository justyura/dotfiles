local set = vim.opt_local

set.expandtab = false
set.tabstop = 4
set.shiftwidth = 4
set.number = true

-- 保存时用 gopls 格式化 + 自动导入
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*.go",
  callback = function()
    -- organize imports
    local params = vim.lsp.util.make_range_params()
    params.context = { only = { "source.organizeImports" } }
    local result = vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 1000)
    for _, res in pairs(result or {}) do
      for _, r in pairs(res.result or {}) do
        if r.edit then
          vim.lsp.util.apply_workspace_edit(r.edit, "utf-16")
        end
      end
    end
    -- format
    vim.lsp.buf.format({ async = false })
  end,
})

-- go mod tidy
vim.keymap.set("n", "<leader>mt", function()
  vim.cmd("!go mod tidy")
end, { desc = "Go mod tidy" })

-- 在右侧终端运行 Go 文件
vim.keymap.set("n", "<leader>r", function()
  local file = vim.fn.expand("%")
  vim.cmd("vsplit")
  vim.cmd("wincmd l")
  vim.cmd("terminal go run " .. file)
  vim.cmd("wincmd h")
end, { desc = "Run Go file in right terminal" })
