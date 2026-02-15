return {
	"stevearc/conform.nvim",
	event = { "BufWritePre" },
	cmd = { "ConformInfo" },
	keys = {
		{
			"<leader>f",
			function()
				require("conform").format({ async = true, lsp_fallback = true })
			end,
			mode = "",
			desc = "Format buffer",
		},
	},
	opts = {
		formatters_by_ft = {
			html = { "prettier" },
			gohtml = { "prettier" },
			css = { "prettier" },
			javascript = { "prettier" },
			typescript = { "prettier" },
			json = { "prettier" },
		},
		-- 保存时自动格式化（可选，取消注释启用）
		-- format_on_save = {
		--   timeout_ms = 500,
		--   lsp_fallback = true,
		-- },
	},
}
