-- Lua DAP configuration
local M = {}

function M.setup(dap)
  local ok, _ = pcall(require, "osv")
  if not ok then
    vim.notify("one-small-step-for-vimkind not installed for Lua debugging", vim.log.levels.WARN)
    return
  end

  dap.adapters.nlua = function(callback, config)
    callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086 })
  end

  dap.configurations.lua = {
    {
      type = "nlua",
      request = "attach",
      name = "Run this file",
      start_neovim = {},
    },
    {
      type = "nlua",
      request = "attach",
      name = "Attach to running Neovim instance (port = 8086)",
      port = 8086,
    },
  }
end

return M
