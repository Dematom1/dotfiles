-- ~/.config/nvim/after/ftplugin/python.lua

local bufnr = vim.api.nvim_get_current_buf()
local map = vim.keymap.set

-- Set Python-specific indentation (reiterating for completeness)
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.expandtab = true

-- Keybinding to open Python REPL (if LSP is attached)
-- This usually uses the LSP's capabilities, or a plugin that provides a REPL.
-- If your LSP (pyright) has a REPL, it will often expose one.
-- Or you might use 'dap.repl.open()' if you're already in a debug session.
-- For a general Python REPL:
map(
  "n",
  "<leader>py", -- p = Python, y = Py (REPL)
  function()
    -- Opens a terminal and runs a Python REPL
    vim.cmd.split()        -- Opens a horizontal split
    vim.cmd.term("python") -- Runs 'python' in the terminal
  end,
  { silent = true, buffer = bufnr, desc = "Python: Open REPL" }
)

-- >>>>>> RUNNABLE-LIKE KEYBINDINGS FOR PYTHON <<<<<<<

-- 1. Run the Current Python File (Recommended: Use terminal directly)
map(
  "n",
  "<leader>pr", -- p = Python, r = Run
  function()
    -- Ensure you are using the correct Python interpreter, e.g., from a venv
    local python_executable = vim.fn.exepath('python')
    if python_executable == '' then
      vim.notify("Python executable not found in PATH!", vim.log.levels.ERROR)
      return
    end

    -- Run the current file in a new terminal split
    -- %:p expands to the full path of the current file
    vim.cmd.split() -- Or vim.cmd.vsplit() for a vertical split
    vim.cmd.term(python_executable .. " " .. vim.fn.expand("%:p"))
    vim.notify("Python script running in terminal...", vim.log.levels.INFO, { title = "Python Runner" })
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run Current File" }
)

-- 2. Run Python File with Arguments (Recommended: Use terminal directly)
map(
  "n",
  "<leader>pa", -- p = Python, a = Arguments
  function()
    vim.ui.input({ prompt = "Arguments: ", default = "" }, function(args)
      if args == nil then return end -- User cancelled

      local python_executable = vim.fn.exepath('python')
      if python_executable == '' then
        vim.notify("Python executable not found in PATH!", vim.log.levels.ERROR)
        return
      end

      vim.cmd.split()
      vim.cmd.term(python_executable .. " " .. vim.fn.expand("%:p") .. " " .. args)
      vim.notify("Python script running with args in terminal...", vim.log.levels.INFO, { title = "Python Runner" })
    end)
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run File with Args" }
)

-- 3. Run Python Tests (Requires Neotest or other test runner)
-- This is a very common and powerful "runnable" in Python development.
-- Assuming you have 'nvim-neotest' installed and configured for Python (e.g., with 'neotest-python')
map(
  "n",
  "<leader>tt", -- t = Test, t = Toggle (Neotest's default for running tests)
  function()
    -- This runs all tests in the current file using neotest.
    -- Ensure neotest.run.run() is configured correctly in your neotest setup.
    require("neotest").run.run(vim.fn.expand("%"))
    vim.notify("Running Python tests...", vim.log.levels.INFO, { title = "Neotest" })
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run File Tests (Neotest)" }
)

map(
  "n",
  "<leader>tn", -- t = Test, n = Nearest (Neotest's default)
  function()
    -- Runs the nearest test to the cursor
    require("neotest").run.run_nearest()
    vim.notify("Running nearest Python test...", vim.log.levels.INFO, { title = "Neotest" })
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run Nearest Test (Neotest)" }
)

-- Example: Pyright-specific rename (already in your config, but including for context)
map(
  "n",
  "<leader>rn", -- WARNING: this conflicts with <leader>pr for "Run Current File" above. Choose one or rename!
  -- Perhaps make this <leader>rn (rename) or <leader>lr (LSP Rename)
  "<cmd>PyrightRename<CR>",
  { buffer = bufnr, desc = "Python: Smart Rename (Pyright)" }
)
