# Neovim Cheatsheet

## Navigation

### Basic Movement
| Keys | Action |
|------|--------|
| `h/j/k/l` | Left/Down/Up/Right |
| `w/b` | Next/Previous word |
| `e` | End of word |
| `0/$` | Start/End of line |
| `gg/G` | Start/End of file |
| `{/}` | Previous/Next paragraph |
| `%` | Matching bracket |
| `<C-d>/<C-u>` | Half page down/up |

### Flash (Quick Jump)
| Keys | Action |
|------|--------|
| `s` | Flash jump (type chars to jump) |
| `S` | Flash treesitter (select by syntax) |
| `r` | Remote flash (operator pending) |

### Code Navigation
| Keys | Action |
|------|--------|
| `]f / [f` | Next/Prev function |
| `]c / [c` | Next/Prev class |
| `]a / [a` | Next/Prev parameter |
| `]s / [s` | Next/Prev symbol (Aerial) |
| `]d / [d` | Next/Prev diagnostic |
| `]h / [h` | Next/Prev git hunk |
| `]t / [t` | Next/Prev TODO comment |

### LSP Navigation
| Keys | Action |
|------|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gR` | Show references |
| `gi` | Show implementations |
| `gt` | Show type definitions |
| `K` | Hover documentation |

---

## Text Objects (Visual Mode)

### Treesitter Objects
| Keys | Action |
|------|--------|
| `vaf / vif` | Select function (outer/inner) |
| `vac / vic` | Select class (outer/inner) |
| `vaa / via` | Select parameter (outer/inner) |
| `vai / vii` | Select conditional (outer/inner) |
| `val / vil` | Select loop (outer/inner) |
| `vab / vib` | Select block (outer/inner) |

### Built-in Objects
| Keys | Action |
|------|--------|
| `viw / vaw` | Select word |
| `vi" / va"` | Select in/around quotes |
| `vi( / va(` | Select in/around parens |
| `vi{ / va{` | Select in/around braces |
| `vit / vat` | Select in/around HTML tag |

### Incremental Selection
| Keys | Action |
|------|--------|
| `<C-space>` | Start/Expand selection |
| `<BS>` | Shrink selection |

---

## Editing

### Surround (nvim-surround)
| Keys | Action |
|------|--------|
| `ys{motion}{char}` | Add surround (e.g., `ysiw"` surrounds word with quotes) |
| `ds{char}` | Delete surround (e.g., `ds"` removes quotes) |
| `cs{old}{new}` | Change surround (e.g., `cs"'` changes " to ') |

### Swap
| Keys | Action |
|------|--------|
| `<leader>sa` | Swap parameter with next |
| `<leader>sA` | Swap parameter with previous |

### Comments
| Keys | Action |
|------|--------|
| `gcc` | Toggle line comment |
| `gc{motion}` | Toggle comment for motion |
| `gbc` | Toggle block comment |

### Other
| Keys | Action |
|------|--------|
| `<leader>+` | Increment number |
| `<leader>-` | Decrement number |

---

## File Management

### Oil (File Browser)
| Keys | Action |
|------|--------|
| `-` | Open parent directory |
| `<CR>` | Open file/directory |
| `g.` | Toggle hidden files |

### FFF (Fuzzy Finder)
| Keys | Action |
|------|--------|
| `<leader>ff` | Find files |
| `<leader>fs` | Live grep |
| `<leader>fz` | Fuzzy live grep |

---

## LSP & Code Actions

| Keys | Action |
|------|--------|
| `<leader>rn` | Rename (with live preview) |
| `<leader>aca` | Code actions |
| `<leader>D` | Buffer diagnostics |
| `<leader>d` | Line diagnostics |
| `<leader>rs` | Restart LSP |
| `<leader>mp` | Format file |

---

## Symbol Navigation (Aerial)

| Keys | Action |
|------|--------|
| `<leader>cs` | Toggle symbol sidebar |
| `<leader>cn` | Toggle floating nav |
| `]s / [s` | Next/Prev symbol |

**Inside Aerial:**
| Keys | Action |
|------|--------|
| `<CR>` | Jump to symbol |
| `o / za` | Toggle fold |
| `l / h` | Open/Close tree |
| `q` | Close |
| `?` | Help |

---

## Git

### Gitsigns (Hunks)
| Keys | Action |
|------|--------|
| `]h / [h` | Next/Prev hunk |
| `<leader>hs` | Stage hunk |
| `<leader>hr` | Reset hunk |
| `<leader>hS` | Stage buffer |
| `<leader>hR` | Reset buffer |
| `<leader>hu` | Undo stage hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line |
| `<leader>hB` | Toggle blame |
| `<leader>hd` | Diff this |
| `ih` | Select hunk (text object) |

### Lazygit
| Keys | Action |
|------|--------|
| `<leader>lg` | Open Lazygit |

---

## Trouble (Diagnostics)

| Keys | Action |
|------|--------|
| `<leader>xw` | Workspace diagnostics |
| `<leader>xd` | Document diagnostics |
| `<leader>xq` | Quickfix list |
| `<leader>xl` | Location list |
| `<leader>xt` | TODOs |

---

## Windows & Tabs

### Splits
| Keys | Action |
|------|--------|
| `<leader>sv` | Split vertical |
| `<leader>sh` | Split horizontal |
| `<leader>se` | Make splits equal |
| `<leader>sx` | Close split |
| `<leader>sm` | Maximize split |
| `<C-h/j/k/l>` | Navigate splits (tmux compatible) |

### Tabs
| Keys | Action |
|------|--------|
| `<leader>to` | New tab |
| `<leader>tx` | Close tab |
| `<leader>tn` | Next tab |
| `<leader>tp` | Previous tab |
| `<leader>tf` | Open file in new tab |

---

## Sessions

| Keys | Action |
|------|--------|
| `<leader>wr` | Restore session |
| `<leader>ws` | Save session |

---

## AI (CodeCompanion)

| Keys | Action |
|------|--------|
| `<leader>ca` | Code actions |
| `<leader>cc` | Chat |
| `<leader>cs` | Toggle chat |

---

## Misc

| Keys | Action |
|------|--------|
| `<leader>hc` | Open this cheatsheet |
| `<leader>nh` | Clear search highlight |
| `jk` | Exit insert mode |
| `n / N` | Next/Prev search (centered) |
| `gl` | Open diagnostic float |

---

## Project Config

Create `.nvim.lua` in project root for local settings.
First time: run `:trust` to allow execution.
