-- ~/.config/nvim/after/ftplugin/rust.lua

local bufnr = vim.api.nvim_get_current_buf()
local map = vim.keymap.set -- For conciseness

map(
  "n",
  "<leader>a",
  function()
    vim.cmd.RustLsp('codeAction')
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Code Actions" }
)

-- Override 'K' for enhanced Rust hover actions (already have this)
map(
  "n",
  "K",
  function()
    vim.cmd.RustLsp({ 'hover', 'actions' })
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Hover & Actions" }
)

-- >>>>>> DEBUGGING KEYBINDINGS FOR RUST <<<<<<<

-- Launch debugger (will prompt if multiple targets or no explicit selection)
-- This is the primary way to start debugging a Rust program.
map(
  "n",
  "<leader>rd", -- r = Rust, d = Debug
  function()
    vim.cmd.RustLsp('debug')
  end,
  { silent = true, buffer = bufnr, desc = "RustDAP: Debug Current Target" }
)

-- Show all debuggable targets in a quick-pick list
-- Useful if your project has multiple binaries, tests, or examples.
map(
  "n",
  "<leader>rD", -- r = Rust, D = Debuggables (uppercase D for list)
  function()
    vim.cmd.RustLsp('debuggables')
  end,
  { silent = true, buffer = bufnr, desc = "RustDAP: Select Debuggable Target" }
)

-- Rerun the last debuggable target (with a bang!)
map(
  "n",
  "<leader>rr", -- r = Rust, r = Rerun
  function()
    vim.cmd.RustLsp { 'debuggables', bang = true }
  end,
  { silent = true, buffer = bufnr, desc = "RustDAP: Rerun Last Debuggable" }
)

-- keymap to start a single test:
map(
  "n",
  "<leader>rt",                  -- r = Rust, t = Test
  function()
    vim.cmd.RustLsp('runnables') -- This often includes tests
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Run Tests" }
)

-- Run current target (e.g., main binary, or specific test under cursor)
map(
  "n",
  "<leader>rc", -- r = Rust, c = run (for 'cargo run')
  function()
    vim.cmd.RustLsp('run')
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Run Current Target" }
)

-- Show all runnable targets in a quick-pick list
map(
  "n",
  "<leader>rC", -- r = Rust, C = Runnables (uppercase C for list)
  function()
    vim.cmd.RustLsp('runnables')
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Select Runnable Target" }
)

-- Rerun the last runnable target
map(
  "n",
  "<leader>rR", -- Let's use '<leader>rR' for RERUN Runnable.
  function()
    vim.cmd.RustLsp { 'runnables', bang = true }
  end,
  { silent = true, buffer = bufnr, desc = "RustLSP: Rerun Last Runnable" }
)
