-- ~/.config/nvim/after/ftplugin/rust.lua

local bufnr = vim.api.nvim_get_current_buf()

-- Rust-specific Code Actions
vim.keymap.set(
  "n",
  "<leader>a",
  function()
    vim.cmd.RustLsp('codeAction') -- Uses rust-analyzer's grouping logic
    -- If you prefer generic LSP code actions without rustaceanvim's grouping:
    -- vim.lsp.buf.code_action()
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Code Actions" }
)

-- Override 'K' for enhanced Rust hover actions
vim.keymap.set(
  "n",
  "K",
  function()
    vim.cmd.RustLsp({ 'hover', 'actions' }) -- Combines hover docs with quick actions
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Hover & Actions" }
)

-- You might add other Rust-specific settings here, e.g.:
-- vim.bo.tabstop = 4 -- Set tabstop to 4 for Rust files
-- vim.bo.shiftwidth = 4
