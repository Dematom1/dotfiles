return {
  "ravitemer/mcphub.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  build = "npm install -g mcp-hub@latest", -- Installs `mcp-hub` node binary globally
  config = function()
    require("mcphub").setup()
    local map = vim.keymap.set

    map("n", "<leader>mc", "<cmd>MCPHub<cr>",
      { noremap = true, silent = true, desc = "MCPHub Ui" })
  end
}
