return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "leoluz/nvim-dap-go",
      "mfussenegger/nvim-dap-python",
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "nvim-neotest/nvim-nio",
      "williamboman/mason.nvim",
      "jay-babu/mason-nvim-dap.nvim",
      {
        "stevearc/overseer.nvim",
        opts = {},
      },
      "jbyuki/one-small-step-for-vimkind",
      -- Remove nvim-dap-vscode-js and vscode-js-debug
      -- Keep lua-json5 if you still want launch.json support
      {
        "Joakker/lua-json5",
        build = "./install.sh",
      },
    },
    opts = {
      ensure_installed = { "cppdbg", "js-debug-adapter", "python" },
      automatic_setup = true,
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      local ui = require("dapui")
      local utils = require("dap.utils")

      -- Helper function to get Mason package path
      local function get_pkg_path(pkg, path)
        pcall(require, 'mason')
        local root = vim.env.MASON or (vim.fn.stdpath('data') .. '/mason')
        path = path or ''
        local ret = root .. '/packages/' .. pkg .. '/' .. path
        return ret
      end

      -- Manual adapter configuration (FIXED APPROACH)
      dap.adapters['pwa-node'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            get_pkg_path('js-debug-adapter', '/js-debug/src/dapDebugServer.js'),
            '${port}',
          },
        },
      }

      dap.adapters['pwa-chrome'] = {
        type = 'server',
        host = 'localhost',
        port = '${port}',
        executable = {
          command = 'node',
          args = {
            get_pkg_path('js-debug-adapter', '/js-debug/src/dapDebugServer.js'),
            '${port}',
          },
        },
      }

      local types_enabled = true
      local toggle_types = function()
        types_enabled = not types_enabled
        require("dapui").update_render({
          max_type_length = types_enabled and -1 or 0,
        })
      end

      require("dap-python").setup("python3")
      require("overseer").setup()

      dap.set_log_level("DEBUG")

      local js_based_languages = {
        "typescript",
        "javascript",
        "typescriptreact",
        "javascriptreact",
      }

      -- Configure JS/TS debugging
      for _, language in ipairs(js_based_languages) do
        dap.configurations[language] = {
          -- Launch file with Bun
          {
            type = "pwa-node",
            request = "launch",
            name = "Launch file with Bun",
            program = "${file}",
            runtimeExecutable = "bun",
            cwd = "${workspaceFolder}",
            sourceMaps = true,
          },
          -- Debug Next.js with Bun
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
          -- Attach to Bun process
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
          -- Client-side debugging
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

      -- LUA configuration
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

      require("dapui").setup({
        icons = { expanded = "▾", collapsed = "▸", current_frame = "*" },
        controls = {
          icons = {
            pause = "⏸",
            play = "▶",
            step_into = "⏎",
            step_over = "⏭",
            step_out = "⏮",
            step_back = "b",
            run_last = "▶▶",
            terminate = "⏹",
            disconnect = "⏏",
          },
        },
      })

      require("nvim-dap-virtual-text").setup({
        commented = true,
      })

      require("dap-go").setup({})

      local map = vim.keymap.set
      map("n", "<space>db", dap.toggle_breakpoint, {
        desc = "DAP: Toggle Breakpoint",
      })
      map("n", "<space>dC", dap.run_to_cursor, { desc = "DAP: Run to Cursor" })
      map("n", "<leader>dc", dap.continue, { desc = "DAP: Continue" })
      map("n", "<leader>df", dap.step_into, { desc = "DAP: Step Into" })
      map("n", "<leader>dd", dap.step_over, { desc = "DAP: Step Over" })
      map("n", "<leader>dg", dap.step_out, { desc = "DAP: Step Out" })
      map("n", "<leader>dB", dap.step_back, { desc = "DAP: Step Back" })
      map("n", "<leader>dr", dap.restart, { desc = "DAP: Restart" })
      map("n", "<leader>dT", dap.terminate, { desc = "DAP: Terminate" })
      map("n", "<leader>dD", dap.disconnect, { desc = "DAP: Disconnect" })
      map("n", "<leader>du", dapui.toggle, { desc = "DAP: Toggle UI" })
      map({ "n", "v" }, "<leader>de", dapui.eval, { desc = "Eval" })
      map({ "n", "v" }, "<leader>dt", function()
        toggle_types()
      end, { desc = "Toggle type" })

      map("n", "<leader>dp", dap.repl.open, { desc = "DAP: Open REPL" })

      -- Auto-open/close UI on debug session
      dap.listeners.before.attach.dapui_config = function()
        ui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        ui.open()
      end
      dap.listeners.after.event_initialized.dapui_config = function()
        dapui.open({ reset = true })
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        ui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        ui.close()
      end
    end,
  },
}
