local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- Set color column at 80 characters
vim.opt.colorcolumn = "80"

-- Highlight it with red background in terminal (ctermbg = 9)
vim.cmd([[highlight ColorColumn ctermbg=9]])

require("lazy").setup({ { import = "laszlohoranszky.plugins" }, { import = "laszlohoranszky.plugins.lsp" } }, {
	checker = {
		enabled = true,
		notify = false,
	},
	change_detection = {
		notify = false,
	},
})
