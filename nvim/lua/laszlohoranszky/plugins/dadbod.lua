return {
  {
    "tpope/vim-dadbod",
    dependencies = {
      "kristijanhusak/vim-dadbod-completion",
      "kristijanhusak/vim-dadbod-ui",
      "hrsh7th/nvim-cmp",
    },
    lazy = true,
    cmd = { "DBUI", "DB" },
    ft = { "sql", "mysql", "psql", "pgsql", "sqlite" },
    -- Add keys to ensure keymaps are available immediately
    keys = {
      { "<leader>sq", "<cmd>DBUI<CR>",                  desc = "Dadbod: Toggle UI" },
      { "<leader>sc", "<cmd>DBUIToggleConnections<CR>", desc = "Dadbod: Toggle Connections Panel" },
      { "<leader>sr", "<cmd>DBUIRenameConnection<CR>",  desc = "Dadbod: Edit Connection" },
    },
    config = function()
      -- Your existing config without the keymaps
      vim.g.db_driver_postgres = 'psql'
      vim.g.db_driver_mysql = 'mysql'
      vim.g.db_driver_sqlite = 'sqlite3'

      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_win_size = 30
      vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui_connections.json"

      -- Keep only the autocmd
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "dbui",
        callback = function()
          vim.keymap.set("n", "q", "<cmd>DBUIQuit<CR>", { buffer = true, desc = "Dadbod: Quit DB UI" })
        end,
      })
    end,
  },
}
