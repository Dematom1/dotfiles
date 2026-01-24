-- JavaScript/TypeScript DAP configuration
local M = {}

function M.setup(dap)
  -- Helper function to get Mason package path
  local function get_pkg_path(pkg, path)
    pcall(require, "mason")
    local root = vim.env.MASON or (vim.fn.stdpath("data") .. "/mason")
    path = path or ""
    return root .. "/packages/" .. pkg .. "/" .. path
  end

  -- Check if js-debug-adapter is installed
  local adapter_path = get_pkg_path("js-debug-adapter", "/js-debug/src/dapDebugServer.js")
  if vim.fn.filereadable(adapter_path) ~= 1 then
    vim.notify("js-debug-adapter not installed. Run :Mason to install.", vim.log.levels.WARN)
    return
  end

  -- Configure adapters
  dap.adapters["pwa-node"] = {
    type = "server",
    host = "localhost",
    port = "${port}",
    executable = {
      command = "node",
      args = { adapter_path, "${port}" },
    },
  }

  dap.adapters["pwa-chrome"] = {
    type = "server",
    host = "localhost",
    port = "${port}",
    executable = {
      command = "node",
      args = { adapter_path, "${port}" },
    },
  }

  -- Configure for JS-based languages
  local js_based_languages = {
    "typescript",
    "javascript",
    "typescriptreact",
    "javascriptreact",
  }

  for _, language in ipairs(js_based_languages) do
    dap.configurations[language] = {
      {
        type = "pwa-node",
        request = "launch",
        name = "Launch file with Bun",
        program = "${file}",
        runtimeExecutable = "bun",
        cwd = "${workspaceFolder}",
        sourceMaps = true,
      },
      {
        type = "pwa-node",
        request = "launch",
        name = "Debug Next.js with Bun",
        runtimeExecutable = "bun",
        runtimeArgs = { "--inspect=127.0.0.1:9229", "run", "dev" },
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**", "node_modules/**" },
        console = "integratedTerminal",
      },
      {
        type = "pwa-node",
        request = "attach",
        name = "Attach to Bun --inspect",
        port = 9229,
        address = "127.0.0.1",
        cwd = "${workspaceFolder}",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**", "node_modules/**" },
      },
      {
        type = "pwa-chrome",
        request = "launch",
        name = "Debug Client in Chrome",
        url = "http://localhost:3000",
        webRoot = "${workspaceFolder}",
        sourceMaps = true,
        skipFiles = { "<node_internals>/**" },
      },
    }
  end
end

return M
