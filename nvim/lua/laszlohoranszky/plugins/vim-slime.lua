-- vim-slime configuration for Neovim (improved version)
-- Add this to your lazy.nvim plugins

return {
  -- slime (REPL integration)
  {
    "jpalardy/vim-slime",
    keys = {
      { "<leader>sC", "<cmd>SlimeConfig<cr>",     desc = "Slime Config" },
      { "<leader>sr", "<Plug>SlimeSendCell",      desc = "Slime Send Cell" },
      { "<leader>sr", ":<C-u>'<,'>SlimeSend<CR>", mode = "v",              desc = "Slime Send Selection" },
      { "<leader>sl", "<Plug>SlimeLineSend",      desc = "Slime Send Line" },
    },
    config = function()
      -- Choose your target (tmux is most reliable)
      vim.g.slime_target = "tmux" -- Change to "neovim" if you prefer built-in terminal

      -- Cell delimiter for Jupyter-style workflow
      vim.g.slime_cell_delimiter = "# %%"

      -- Enable bracketed paste for better terminal handling
      vim.g.slime_bracketed_paste = 1

      -- Don't ask for confirmation (optional)
      vim.g.slime_dont_ask_default = 1

      -- Default tmux config
      vim.g.slime_default_config = {
        socket_name = "default",
        target_pane = "{last}"
      }

      -- Uncomment these lines if you want to use neovim target instead:
      -- vim.g.slime_target = "neovim"
      -- vim.g.slime_neovim_ignore_unlisted = 1
      -- vim.g.slime_default_config = { jobid = nil }
    end,
  },
}

-- Usage:
-- 1. With tmux: Start tmux, open nvim, create a pane with your REPL
-- 2. With neovim: Use :split | terminal python in nvim
-- 3. Use # %% to create cells in your code
-- 4. <leader>rr to send current cell
-- 5. <leader>rl to send current line
-- 6. Ctrl+c Ctrl+c to send selection or paragraph
