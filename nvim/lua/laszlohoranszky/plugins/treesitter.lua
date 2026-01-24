return {
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPre", "BufNewFile" },
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      local treesitter = require("nvim-treesitter.configs")

      treesitter.setup({
        -- enable autotagging (w/ nvim-ts-autotag plugin)
        autotag = { enable = true },
        fold = { enable = true },
        modules = {},
        sync_install = false,
        ignore_install = {},

        -- ensure these language parsers are installed
        ensure_installed = {
          "json",
          "javascript",
          "typescript",
          "tsx",
          "yaml",
          "html",
          "css",
          "prisma",
          "markdown",
          "markdown_inline",
          "svelte",
          "graphql",
          "bash",
          "lua",
          "python",
          "vim",
          "go",
          "r",
          "dockerfile",
          "gitignore",
          "query",
          "vimdoc",
          "c",
          "make",
          "regex",
          "zig",
        },

        incremental_selection = {
          enable = true,
          keymaps = {
            init_selection = "<C-space>",
            node_incremental = "<C-space>",
            scope_incremental = false,
            node_decremental = "<bs>",
          },
        },

        auto_install = true,
        highlight = {
          enable = true,
          additional_vim_regex_highlighting = false,
        },
        indent = { enable = true },

        -- Textobjects configuration
        textobjects = {
          select = {
            enable = true,
            lookahead = true, -- Jump forward to textobj
            keymaps = {
              ["af"] = { query = "@function.outer", desc = "Select outer function" },
              ["if"] = { query = "@function.inner", desc = "Select inner function" },
              ["ac"] = { query = "@class.outer", desc = "Select outer class" },
              ["ic"] = { query = "@class.inner", desc = "Select inner class" },
              ["aa"] = { query = "@parameter.outer", desc = "Select outer parameter" },
              ["ia"] = { query = "@parameter.inner", desc = "Select inner parameter" },
              ["ai"] = { query = "@conditional.outer", desc = "Select outer conditional" },
              ["ii"] = { query = "@conditional.inner", desc = "Select inner conditional" },
              ["al"] = { query = "@loop.outer", desc = "Select outer loop" },
              ["il"] = { query = "@loop.inner", desc = "Select inner loop" },
              ["ab"] = { query = "@block.outer", desc = "Select outer block" },
              ["ib"] = { query = "@block.inner", desc = "Select inner block" },
            },
          },
          move = {
            enable = true,
            set_jumps = true, -- Add to jumplist
            goto_next_start = {
              ["]f"] = { query = "@function.outer", desc = "Next function start" },
              ["]c"] = { query = "@class.outer", desc = "Next class start" },
              ["]a"] = { query = "@parameter.inner", desc = "Next parameter" },
            },
            goto_next_end = {
              ["]F"] = { query = "@function.outer", desc = "Next function end" },
              ["]C"] = { query = "@class.outer", desc = "Next class end" },
            },
            goto_previous_start = {
              ["[f"] = { query = "@function.outer", desc = "Previous function start" },
              ["[c"] = { query = "@class.outer", desc = "Previous class start" },
              ["[a"] = { query = "@parameter.inner", desc = "Previous parameter" },
            },
            goto_previous_end = {
              ["[F"] = { query = "@function.outer", desc = "Previous function end" },
              ["[C"] = { query = "@class.outer", desc = "Previous class end" },
            },
          },
          swap = {
            enable = true,
            swap_next = {
              ["<leader>sa"] = { query = "@parameter.inner", desc = "Swap with next parameter" },
            },
            swap_previous = {
              ["<leader>sA"] = { query = "@parameter.inner", desc = "Swap with previous parameter" },
            },
          },
        },
      })
    end,
  },
  { "nvim-treesitter/nvim-treesitter-context" },
}
