-- ~/.config/nvim/after/ftplugin/python.lua
local bufnr = vim.api.nvim_get_current_buf()
local map = vim.keymap.set

-- Set Python-specific indentation
vim.opt_local.tabstop = 4
vim.opt_local.shiftwidth = 4
vim.opt_local.expandtab = true

-- Keybinding to open Python REPL
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

-- Enhanced REPL with uv support
map(
  "n",
  "<leader>pu", -- p = Python, u = UV REPL
  function()
    -- Check if uv project exists and use uv run python
    if vim.fn.filereadable('pyproject.toml') == 1 or vim.fn.filereadable('uv.lock') == 1 then
      vim.cmd.split()
      vim.cmd.term("uv run python")
      vim.notify("Opening UV Python REPL...", vim.log.levels.INFO)
    else
      vim.cmd.split()
      vim.cmd.term("python")
      vim.notify("Opening system Python REPL...", vim.log.levels.INFO)
    end
  end,
  { silent = true, buffer = bufnr, desc = "Python: Open UV/System REPL" }
)

-- >>>>>> RUNNABLE-LIKE KEYBINDINGS FOR PYTHON <<<<<<<

-- 1. Run the Current Python File
map(
  "n",
  "<leader>pr", -- p = Python, r = Run
  function()
    local python_cmd
    -- Check for uv project
    if vim.fn.filereadable('pyproject.toml') == 1 or vim.fn.filereadable('uv.lock') == 1 then
      python_cmd = "uv run python"
    else
      local python_executable = vim.fn.exepath('python')
      if python_executable == '' then
        vim.notify("Python executable not found in PATH!", vim.log.levels.ERROR)
        return
      end
      python_cmd = python_executable
    end

    vim.cmd.split()
    vim.cmd.term(python_cmd .. " " .. vim.fn.expand("%:p"))
    vim.notify("Python script running in terminal...", vim.log.levels.INFO, { title = "Python Runner" })
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run Current File" }
)

-- 2. Run Python File with Arguments
map(
  "n",
  "<leader>pa", -- p = Python, a = Arguments
  function()
    vim.ui.input({ prompt = "Arguments: ", default = "" }, function(args)
      if args == nil then return end -- User cancelled

      local python_cmd
      if vim.fn.filereadable('pyproject.toml') == 1 or vim.fn.filereadable('uv.lock') == 1 then
        python_cmd = "uv run python"
      else
        local python_executable = vim.fn.exepath('python')
        if python_executable == '' then
          vim.notify("Python executable not found in PATH!", vim.log.levels.ERROR)
          return
        end
        python_cmd = python_executable
      end

      vim.cmd.split()
      vim.cmd.term(python_cmd .. " " .. vim.fn.expand("%:p") .. " " .. args)
      vim.notify("Python script running with args in terminal...", vim.log.levels.INFO, { title = "Python Runner" })
    end)
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run File with Args" }
)

-- 3. Run Python Tests (Requires Neotest)
map(
  "n",
  "<leader>tt", -- t = Test, t = Toggle
  function()
    if pcall(require, "neotest") then
      require("neotest").run.run(vim.fn.expand("%"))
      vim.notify("Running Python tests...", vim.log.levels.INFO, { title = "Neotest" })
    else
      -- Fallback to pytest if neotest isn't available
      local pytest_cmd
      if vim.fn.filereadable('pyproject.toml') == 1 or vim.fn.filereadable('uv.lock') == 1 then
        pytest_cmd = "uv run pytest"
      else
        pytest_cmd = "pytest"
      end

      vim.cmd.split()
      vim.cmd.term(pytest_cmd .. " " .. vim.fn.expand("%:p"))
      vim.notify("Running pytest...", vim.log.levels.INFO)
    end
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run File Tests" }
)

map(
  "n",
  "<leader>tn", -- t = Test, n = Nearest
  function()
    if pcall(require, "neotest") then
      require("neotest").run.run()
      vim.notify("Running nearest Python test...", vim.log.levels.INFO, { title = "Neotest" })
    else
      vim.notify("Neotest not available", vim.log.levels.WARN)
    end
  end,
  { silent = true, buffer = bufnr, desc = "Python: Run Nearest Test" }
)

-- 4. Interactive Python (IPython if available)
map(
  "n",
  "<leader>pi", -- p = Python, i = Interactive
  function()
    local ipython_cmd
    if vim.fn.filereadable('pyproject.toml') == 1 or vim.fn.filereadable('uv.lock') == 1 then
      -- Check if ipython is available in uv environment
      local handle = io.popen('uv run which ipython 2>/dev/null')
      if handle then
        local result = handle:read('*a'):gsub('%s+', '')
        handle:close()
        if result ~= '' then
          ipython_cmd = "uv run ipython"
        else
          ipython_cmd = "uv run python"
        end
      else
        ipython_cmd = "uv run python"
      end
    else
      -- Check system ipython
      if vim.fn.exepath('ipython') ~= '' then
        ipython_cmd = "ipython"
      else
        ipython_cmd = "python"
      end
    end

    vim.cmd.split()
    vim.cmd.term(ipython_cmd)
    vim.notify("Opening interactive Python...", vim.log.levels.INFO)
  end,
  { silent = true, buffer = bufnr, desc = "Python: Open IPython/Interactive" }
)

-- LSP-specific keybindings (fixed conflict)
map(
  "n",
  "<leader>rn", -- r = Rename, n = Name
  function()
    if vim.lsp.buf.rename then
      vim.lsp.buf.rename()
    else
      vim.cmd("PyrightRename")
    end
  end,
  { buffer = bufnr, desc = "Python: Smart Rename" }
)
