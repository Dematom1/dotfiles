-- ~/.config/nvim/lua/plugins/codecompanion.lua

return {
  "olimorris/codecompanion.nvim",
  -- `opts = {}` here means you could add global setup options later if needed.
  opts = {},
  dependencies = {
    "nvim-lua/plenary.nvim",           -- General utility library (common dependency)
    "nvim-treesitter/nvim-treesitter", -- Used by CodeCompanion for parsing
    "ravitemer/mcphub.nvim",           -- Another dependency of CodeCompanion
    -- Render markdown (explicitly loads for codecompanion filetype)
    {
      "MeanderingProgrammer/render-markdown.nvim",
      ft = { "markdown", "codecompanion" }
    },
    -- mini.diff (configured to be disabled by default)
    {
      "echasnovski/mini.diff",
      config = function()
        local diff = require("mini.diff")
        diff.setup({
          source = diff.gen_source.none(), -- Disabled by default
        })
      end,
    },
    -- img-clip.nvim (configured for codecompanion filetype)
    {
      "HakonHarnes/img-clip.nvim",
      opts = {
        filetypes = {
          codecompanion = {
            prompt_for_file_name = false,
            template = "[Image]($FILE_PATH)",
            use_absolute_path = true,
          },
        },
      },
    },
  },
  config = function(opts)
    require("codecompanion").setup(opts)
    -- Keymaps for CodeCompanion
    local map = vim.keymap.set

    -- Keymap for CodeCompanion Actions
    -- This will open a Telescope/FZF-like picker for actions.
    map({ "n", "v" }, "<leader>ca", "<cmd>CodeCompanionActions<cr>",
      { noremap = true, silent = true, desc = "CodeCompanion: Actions" })

    -- Keymap to Toggle CodeCompanion Chat Window
    map({ "n", "v" }, "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>",
      { noremap = true, silent = true, desc = "CodeCompanion: Toggle Chat" })

    -- Visual Mode keymap to Add selected text to CodeCompanion Chat
    map("v", "<leader>cs", "<cmd>CodeCompanionChat Add<cr>",
      { noremap = true, silent = true, desc = "CodeCompanion: Send Selection" })

    -- Command-line Aliases
    vim.cmd([[cab cc CodeCompanion]])
    vim.cmd([[cab ccc CodeCompanionChat]])
  end,
}
