return {
  "smjonas/inc-rename.nvim",
  cmd = "IncRename",
  keys = {
    {
      "<leader>rn",
      function()
        return ":IncRename " .. vim.fn.expand("<cword>")
      end,
      expr = true,
      desc = "Rename (with preview)",
    },
  },
  opts = {
    input_buffer_type = "dressing", -- Uses dressing.nvim if available
  },
}
