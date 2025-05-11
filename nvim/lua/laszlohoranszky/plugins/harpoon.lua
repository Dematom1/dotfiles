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
			for _, idx in ipairs({ 1, 2, 3, 4, 5 }) do
				vim.keymap.set("n", string.format("<space>%d", idx), function()
					harpoon:list():select(idx)
				end)
			end
		end,
	},
}
