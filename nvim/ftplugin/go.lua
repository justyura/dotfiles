vim.api.nvim_create_autocmd('BufWritePre', {
	buffer = 0,
	callback = function(args)
		-- organize imports synchronously so the edit lands before the buffer is written
		local client = vim.lsp.get_clients({ bufnr = args.buf, name = 'gopls' })[1]
		if not client then return end
		local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
		params.context = { only = { 'source.organizeImports' }, diagnostics = {} }
		local resp = client:request_sync('textDocument/codeAction', params, 1000, args.buf)
		for _, action in ipairs(resp and resp.result or {}) do
			if action.edit then
				vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
			end
		end
		vim.lsp.buf.format({ bufnr = args.buf })
	end,
})

-- Go-specific settings
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.expandtab = false

-- quick validate ideas
vim.keymap.set("n", "<leader>r", function()
	local file = vim.fn.expand("%")
	vim.cmd("vsplit")
	vim.cmd("wincmd l")
	vim.cmd("terminal go run " .. file)
	vim.cmd("wincmd h")
end, { buffer = true, desc = "Run Go file in right terminal" })
