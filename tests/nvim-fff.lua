local called = false
package.loaded.fff = {
	live_grep = function(opts)
		assert(opts == nil, "<leader>fs changed live_grep options")
		called = true
	end,
}

local mapping = vim.fn.maparg("<leader>fs", "n", false, true)
assert(mapping.callback ~= nil, "<leader>fs is not mapped in normal mode")
vim.api.nvim_feedkeys(vim.keycode("<leader>fs"), "x", false)
assert(called, "<leader>fs does not invoke fff.live_grep")
print("Neovim fff mapping regression passed")
vim.cmd.quitall()
