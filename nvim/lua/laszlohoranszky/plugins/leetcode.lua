return {
  "kawre/leetcode.nvim",
  build = ":TSUpdate html", -- if you have `nvim-treesitter` installed
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  opts = {
    -- configuration goes here
  },
}
