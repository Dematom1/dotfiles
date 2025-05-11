return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"leoluz/nvim-dap-go",
			"rcarriga/nvim-dap-ui",
			"theHamsta/nvim-dap-virtual-text",
			"nvim-neotest/nvim-nio",
			"williamboman/mason.nvim",
		},
		config = function()
			local dap = require("dap")
			local ui = require("dapui")

			require("dapui").setup()
			require("dap-go").setup()

			local map = vim.keymap.set
			map("n", "<space>db", dap.toggle_breakpoint, { desc = "DAP: Toggle Breakpoint" })
			map("n", "<space>dC", dap.run_to_cursor, { desc = "DAP: Run to Cursor" })
			map("n", "<space>?", function()
				ui.eval(nil, { enter = true })
			end, { desc = "DAP: Evaluate Variable" })

			map("n", "<leader>dc", dap.continue, { desc = "DAP: Continue" })
			map("n", "<leader>df", dap.step_into, { desc = "DAP: Step Into" })
			map("n", "<leader>dd", dap.step_over, { desc = "DAP: Step Over" })
			map("n", "<leader>dg", dap.step_out, { desc = "DAP: Step Out" })
			map("n", "<leader>dB", dap.step_back, { desc = "DAP: Step Back" })
			map("n", "<leader>dr", dap.restart, { desc = "DAP: Restart" })
			map("n", "<leader>dT", dap.terminate, { desc = "DAP: Terminate" })

			-- Optional: open REPL
			map("n", "<leader>dp", dap.repl.open, { desc = "DAP: Open REPL" })

			-- Auto-open/close UI on debug session
			dap.listeners.before.attach.dapui_config = function()
				ui.open()
			end
			dap.listeners.before.launch.dapui_config = function()
				ui.open()
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
