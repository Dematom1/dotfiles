return {
  "mistweaverco/kulala.nvim",
  keys = {
    { "<leader>Rs", "<cmd>Kulala send_request<CR>",      desc = "Kulala: Send Request" },      -- Send request under cursor
    { "<leader>Ra", "<cmd>Kulala send_all_requests<CR>", desc = "Kulala: Send All Requests" }, -- Send all requests in file
    { "<leader>Rb", "<cmd>Kulala scratchpad<CR>",        desc = "Kulala: Open Scratchpad" },   -- Open scratchpad
    -- Optional: You might want to bind a key to 'Kulala chat' if it has one, for interactive chat.
    -- Example: { "<leader>pc", "<cmd>Kulala chat<CR>", desc = "Kulala: Chat" },
  },
  ft = { "http", "rest" },
  opts = {
    global_keymaps = true,
    global_keymaps_prefix = "<leader>R",
    kulala_keymaps_prefix = "",
  },
}
