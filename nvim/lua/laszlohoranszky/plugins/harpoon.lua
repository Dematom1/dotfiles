return {
	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope.nvim",
		},
		config = function()
			local harpoon = require("harpoon")

			---@diagnostic disable-next-line: missing-parameter
			harpoon:setup()

			require("telescope").load_extension("harpoon")

			local map = vim.keymap.set
			local opts = { noremap = true, silent = true }

			map("n", "<leader>a", function()
				harpoon:list():add()
			end, { desc = "Harpoon add file" })
			map("n", "<leader>h", function()
				harpoon.ui:toggle_quick_menu(harpoon:list())
			end, { desc = "Harpoon menu" })

			map("n", "<C-h><C-h>", function()
				harpoon:list():select(1)
			end, opts)
			map("n", "<C-h><C-j>", function()
				harpoon:list():select(2)
			end, opts)
			map("n", "<C-h><C-k>", function()
				harpoon:list():select(3)
			end, opts)
			map("n", "<C-h><C-l>", function()
				harpoon:list():select(4)
			end, opts)
		end,
	},
}
