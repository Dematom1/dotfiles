-- lua/plugins/floaterm.lua (or similar)

return {
  "voldikss/vim-floaterm",
  -- Keymap to toggle a floaterm window.
  keys = {
    { "<leader>ft", "<cmd>FloatermToggle<CR>",                                                   desc = "Toggle Floaterm" },
    { "<leader>fs", "<cmd>FloatermNew --title=Shell --height=0.8 --width=0.8 --autoclose=0<CR>", desc = "New Shell Floaterm" },
    { "<leader>fk", "<cmd>FloatermKill<CR>",                                                     desc = "Kill Floaterm Process" },
    -- Add more floaterm specific keybindings if needed
  },
  config = function()
    -- Global Floaterm settings (optional)
    vim.g.floaterm_key_toggle = "<leader>ft" -- Already defined above, but good to know this option exists
    vim.g.floaterm_width = 0.8               -- 80% of screen width
    vim.g.floaterm_height = 0.8              -- 80% of screen height
    vim.g.floaterm_position = "center"       -- Center the window
    vim.g.floaterm_border = "single"         -- Use a single-line border
    vim.g.flofloaterm_wintype = "float"      -- Ensure it's a floating window
    vim.g.floaterm_autoclose = 1


    -- Autoclose options (important for 'run' commands)
    -- 0: Never close automatically
    -- 1: Close after exit
    -- 2: Close after exit unless there's an error
    vim.g.floaterm_autoclose = 1                    -- Default to closing after the command exits
    vim.g.floaterm_default_options = "--cwd=<root>" -- Default all new floaterms to project root

    -- Example: Set background transparency (requires specific Neovim builds/config for true transparency)
    -- vim.api.nvim_set_hl(0, "FloatermBorder", { bg = "none", fg = "#888888" })
    -- vim.api.nvim_set_hl(0, "FloatermNC", { bg = "none", fg = "#aaaaaa" })
  end,
}
