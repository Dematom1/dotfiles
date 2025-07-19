return {
  "hrsh7th/nvim-cmp",
  name = "cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-buffer",                  -- source for text in buffer
    "hrsh7th/cmp-path",                    -- source for file system paths
    "hrsh7th/cmp-nvim-lsp",                -- This is generally recommended, although nvim_lsp source covers it. Good to explicitly have.
    "hrsh7th/cmp-nvim-lua",                -- <<-- NEW: For Neovim Lua API completion
    "hrsh7th/cmp-nvim-lsp-signature-help", -- <<-- NEW: For LSP signature help
    "hrsh7th/cmp-calc",
    "hrsh7th/cmp-vsnip",
    {
      "L3MON4D3/LuaSnip",
      version = "v2.*",
      build = "make install_jsregexp",
    },
    "saadparwaiz1/cmp_luasnip",     -- for autocompletion
    "rafamadriz/friendly-snippets", -- useful snippets
    "onsails/lspkind.nvim",         -- vs-code like pictograms
  },
  config = function()
    local cmp = require("cmp")
    local luasnip = require("luasnip")
    local lspkind = require("lspkind")

    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      completion = {
        completeopt = "menu,menuone,preview,noselect",
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
        ["<S-Tab>"] = cmp.mapping.select_prev_item(), -- selects the previous item.
        ["<Tab>"] = cmp.mapping.select_next_item(),   -- Tab also selects the next item.
      }),
      sources = cmp.config.sources({
        { name = "nvim_lsp",                   keyword_length = 3 },
        { name = "luasnip" },
        { name = "nvim_lsp_signature_help" }, -- display function signatures with current parameter emphasized
        { name = "buffer",                     keyword_length = 2 },
        { name = "path",                       keyword_length = 2 },
        { name = "nvim_lua",                   keyword_length = 2 }, -- <<-- NEW: Enable nvim_lua source
        { name = "cmp_nvim_lsp_signature_help" },                    -- <<-- NEW: Enable signature help source
        { name = "vsnip",                      keyword_length = 2 }, -- nvim-cmp source for vim-vsnip
        { name = "calc" },                                           -- source for math calculation
      }),
      formatting = {
        fields = { "menu", "abbr", "kind" },
        format = function(entry, item)
          local menu_icon = {
            nvim_lsp = "λ",
            vsnip = "⋗",
            buffer = "Ω",
            path = "🖫",
            calc = "+",
            nvim_lua = "∞",
            cmp_nvim_lsp_signature_help = "✎",
            dadbod = "🗄", -- dadbod
          }
          item.menu = menu_icon[entry.source.name]
          return item
        end,
      },
    })
    cmp.setup.filetype({ "sql", "mysql", "psql", "pgsql", "sqlite" }, {
      sources = cmp.config.sources({
        { name = "dadbod" },                                   -- SQL-specific completion from Dadbod
        { name = "buffer",               keyword_length = 2 }, -- Still useful for words in the current SQL buffer
        { name = "path" },                                     -- Path completion can sometimes be useful even in SQL
        { name = "vim-dadbod-completion" },
        -- You could also include 'nvim_lsp' here if you have an SQL LSP server setup (like sqls)
        -- { name = "nvim_lsp" },
      }),
      -- You can override other settings here for SQL, e.g., mapping specific keys
      -- mapping = cmp.mapping.preset.insert({
      --   ["<C-j>"] = cmp.mapping.select_next_item(), -- Example: override key for SQL only
      -- }),
    })
  end,
}
