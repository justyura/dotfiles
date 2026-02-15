return {
  -- 1. LSP 基础依赖
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      {
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
          library = {
            { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          },
        },
      },
    },
  },

  -- 2. 括号自动配对
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
        disable_filetype = { "TelescopePrompt", "vim" },
      })
    end,
  },

  -- 3. 自动补全（重要！）
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",        -- LSP 补全源
      "hrsh7th/cmp-buffer",           -- 缓冲区补全
      "hrsh7th/cmp-path",             -- 路径补全
      "L3MON4D3/LuaSnip",             -- 代码片段引擎
      "saadparwaiz1/cmp_luasnip",    -- 代码片段补全源
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          -- Tab 补全
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          -- Shift+Tab 反向选择
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },    -- LSP 补全
          { name = "luasnip" },      -- 代码片段
        }, {
          { name = "buffer" },       -- 缓冲区单词
          { name = "path" },         -- 文件路径
        }),
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
      })

      -- 集成 nvim-autopairs
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },

  -- 4. LSP 服务器配置
  {
    "neovim/nvim-lspconfig",
    config = function()
      -- 配置诊断显示
      vim.diagnostic.config({
        virtual_text = {
          prefix = '●',
          source = "if_many",
        },
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
          header = "",
          prefix = "",
        },
      })

      -- 设置诊断符号
      local signs = { 
        Error = " ", 
        Warn = " ", 
        Hint = "󰌵 ", 
        Info = " " 
      }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      -- 获取 cmp 的 capabilities
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- 按键映射
      local on_attach = function(_, bufnr)
        local opts = { buffer = bufnr, noremap = true, silent = true }

        -- 诊断快捷键
        vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)
        vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, opts)

        -- LSP 功能快捷键
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
        vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
        vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
        vim.keymap.set("n", "<leader>D", vim.lsp.buf.type_definition, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<leader>f", function()
          vim.lsp.buf.format { async = true }
        end, opts)
      end

      -- Lua LSP
      require("lspconfig").lua_ls.setup({
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = {
              enable = false,
            },
          },
        },
      })

      -- Go LSP (gopls)
      require("lspconfig").gopls.setup({
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
          gopls = {
            -- 格式化
            gofumpt = true,              -- 更严格的格式化

            -- 补全
            completeUnimported = true,   -- 自动导入包
            usePlaceholders = true,      -- 函数参数占位符

            -- 代码分析
            analyses = {
              unusedparams = true,       -- 未使用参数
              shadow = true,              -- 变量覆盖
              nilness = true,             -- 空指针检查
              unusedwrite = true,         -- 未使用的赋值
	      modernize = false,
            },

            -- 静态检查
            staticcheck = true,

            -- 代码提示 (inlay hints)
            hints = {
              assignVariableTypes = true,
              compositeLiteralFields = true,
              constantValues = true,
              functionTypeParameters = true,
              parameterNames = true,
              rangeVariableTypes = true,
            },

            -- 代码透镜
            codelenses = {
              gc_details = false,
              generate = true,
              regenerate_cgo = true,
              run_govulncheck = true,
              test = true,
              tidy = true,
              upgrade_dependency = true,
              vendor = true,
            },
          },
        },
      })

      -- Configure filetype detection
      vim.filetype.add({
	extension = {
	  gohtml = 'html',
	},
      })

      require('lspconfig').html.setup({
	filetypes = { 'html', 'gohtml' },
	capabilities = require('cmp_nvim_lsp').default_capabilities(),
	settings = {
	  html = {
	    format = {
	      enable = true,
	    },
	    hover = {
	      documentation = true,
	      references = true,
	    },
	  },
	},
      })
    end,
  },
}

