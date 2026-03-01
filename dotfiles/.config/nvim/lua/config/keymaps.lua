-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.g.mapleader = " "

local keymap = vim.keymap -- for conciseness
-- use jk to exit insert mode
keymap.set("i", "jk", "<ESC>", { desc = "Exit insert mode with jk" })
keymap.set("t", "jk", "<C-\\><C-n>", { desc = "exit terminal mode with jk" }) -- decrement

-- -- increment/decrement numbers
-- keymap.set("n", "<leader>+", "<C-a>", { desc = "Increment number" }) -- increment
-- keymap.set("n", "<leader>-", "<C-x>", { desc = "Decrement number" }) -- decrement

-- resize using alt hjkl
keymap.set("n", "<M-h>", "2<C-w><", { desc = "Resize window left" })
keymap.set("n", "<M-l>", "1<C-w>>", { desc = "Resize window right" })
keymap.set("n", "<M-j>", "3<C-w>-", { desc = "Resize window down" })
keymap.set("n", "<M-k>", "2<C-w>+", { desc = "Resize window up" })
