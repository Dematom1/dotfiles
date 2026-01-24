-- Python DAP configuration
local M = {}

function M.setup()
  local function get_python_path()
    -- Check if uv project exists
    if vim.fn.filereadable("pyproject.toml") == 1 or vim.fn.filereadable("uv.lock") == 1 then
      local handle = io.popen("uv run which python 2>/dev/null")
      if handle then
        local path = handle:read("*a"):gsub("\n", "")
        handle:close()
        if path ~= "" then
          return path
        end
      end
    end
    -- Fallback to system python
    return "python3"
  end

  local ok, dap_python = pcall(require, "dap-python")
  if not ok then
    vim.notify("dap-python not installed", vim.log.levels.WARN)
    return
  end

  dap_python.setup(get_python_path())
end

return M
