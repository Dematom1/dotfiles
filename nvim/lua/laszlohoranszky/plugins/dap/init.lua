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
      { "stevearc/overseer.nvim", opts = {} },
      "jbyuki/one-small-step-for-vimkind",
      { "Joakker/lua-json5", build = "./install.sh" },
    },
    opts = {
      ensure_installed = { "cppdbg", "js-debug-adapter", "python" },
      automatic_setup = true,
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      -- Set log level for debugging issues
      dap.set_log_level("DEBUG")

      -- Setup overseer for task running
      local ok_overseer, overseer = pcall(require, "overseer")
      if ok_overseer then
        overseer.setup()
      end

      -- Load language-specific configurations
      require("laszlohoranszky.plugins.dap.javascript").setup(dap)
      require("laszlohoranszky.plugins.dap.python").setup()
      require("laszlohoranszky.plugins.dap.lua").setup(dap)
      require("laszlohoranszky.plugins.dap.r").setup(dap)
      require("laszlohoranszky.plugins.dap.go").setup()

      -- Setup DAP UI
      dapui.setup({
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

      -- Setup virtual text
      local ok_vt, vt = pcall(require, "nvim-dap-virtual-text")
      if ok_vt then
        vt.setup({ commented = true })
      end

      -- Toggle types helper
      local types_enabled = true
      local function toggle_types()
        types_enabled = not types_enabled
        dapui.update_render({ max_type_length = types_enabled and -1 or 0 })
      end

      -- Keymaps
      local map = vim.keymap.set
      map("n", "<space>db", dap.toggle_breakpoint, { desc = "DAP: Toggle Breakpoint" })
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
      map({ "n", "v" }, "<leader>de", dapui.eval, { desc = "DAP: Eval" })
      map({ "n", "v" }, "<leader>dt", toggle_types, { desc = "DAP: Toggle type" })
      map("n", "<leader>dp", dap.repl.open, { desc = "DAP: Open REPL" })

      -- Auto-open/close UI on debug session
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.after.event_initialized.dapui_config = function()
        dapui.open({ reset = true })
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
    end,
  },
}
