#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

DOTFILES_ROOT="$repo" nvim --headless -u NONE -l - <<'LUA'
local root = assert(vim.env.DOTFILES_ROOT)
local spec = dofile(root .. "/nvim/lua/laszlohoranszky/plugins/fff.lua")
local mappings = {}
for _, mapping in ipairs(spec.keys) do
	mappings[mapping[1]] = mapping
end

for _, lhs in ipairs({ "<leader>ff", "<leader>fs", "<leader>fz" }) do
	assert(mappings[lhs], lhs .. " mapping is missing")
end
assert(not mappings.fs, "bare fs mapping regressed")

local called = false
package.loaded.fff = {
	live_grep = function(opts)
		assert(opts == nil, "<leader>fs changed live_grep options")
		called = true
	end,
}
mappings["<leader>fs"][2]()
assert(called, "<leader>fs does not invoke fff.live_grep")
print("Neovim fff mapping regression passed")
LUA
