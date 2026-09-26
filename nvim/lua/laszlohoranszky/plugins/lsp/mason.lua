return {
	"williamboman/mason.nvim",
	dependencies = {
		"williamboman/mason-lspconfig.nvim",
		"WhoIsSethDaniel/mason-tool-installer.nvim",
	},
	config = function()
		-- import mason
		local mason = require("mason")

		-- import mason-lspconfig
		local mason_lspconfig = require("mason-lspconfig")

		local mason_tool_installer = require("mason-tool-installer")
		-- enable mason and configure icons
		mason.setup({
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		})

		-- Runtime guard: never auto-enable a server whose language runtime is
		-- missing. On Neovim 0.11+ vim.lsp.enable() runs the server's root_dir on
		-- file open, and gopls (via nvim-lspconfig) shells out to `go`, which
		-- hard-crashes the editor with a Lua traceback when `go` is absent. When
		-- the runtime is present the server auto-enables normally.
		local automatic_enable = true
		if vim.fn.executable("go") == 0 then
			automatic_enable = { exclude = { "gopls" } }
		end

		mason_lspconfig.setup({
			-- list of servers for mason to install
			ensure_installed = {
				"html",
				"cssls",
				"tailwindcss",
				"graphql",
				"gopls",
				"templ",
				"prismals",
				"basedpyright",
				"jsonls",
				"dockerls",
				"marksman",
				"ruff",
				"bashls",
				"helm_ls",
				"rust_analyzer",
				"jinja_lsp",
				"ts_ls",
				"oxlint",
				"docker_compose_language_service",
				"zls",
				"eslint",
				"emmet_ls",
				"lua_ls",
				"gitlab_ci_ls",
			},
			-- Use new vim.lsp.enable() under the hood (Neovim 0.11+).
			-- Guarded above so a missing language runtime cannot crash the editor.
			automatic_enable = automatic_enable,
		})

		mason_tool_installer.setup({
			ensure_installed = {
				"prettier", -- prettier formatter
				"ruff", -- python
				"eslint_d", -- js linter
				"biome", -- js/ts linter + formatter
				"stylua", -- lua formatter
				"luacheck", -- lua linter
				"shfmt", -- shell formatter
				"goimports", -- go formatter
			},
		})
	end,
}
