-- R DAP configuration
local M = {}

function M.setup(dap)
  -- Check if R is available
  if vim.fn.executable("R") ~= 1 then
    return -- Silently skip if R not installed
  end

  dap.adapters.r = {
    type = "executable",
    command = "R",
    args = { "--slave", "-e", "vscDebugger::.vsc.listen()" },
  }

  dap.configurations.r = {
    {
      type = "r",
      request = "launch",
      name = "Launch R",
      program = "${file}",
      console = "integratedTerminal",
    },
  }
end

return M
