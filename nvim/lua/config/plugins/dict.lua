local function dict_lookup()
  local word = vim.fn.expand("<cword>")
  local output = vim.fn.systemlist("dict -d wn " .. word)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " dict: " .. word .. " ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, silent = true })
end

vim.keymap.set("n", "<Leader>d", dict_lookup, { desc = "Dictionary lookup" })

return {}
