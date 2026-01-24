-- Go DAP configuration
local M = {}

function M.setup()
  local ok, dap_go = pcall(require, "dap-go")
  if not ok then
    vim.notify("dap-go not installed", vim.log.levels.WARN)
    return
  end

  dap_go.setup({})
end

return M
