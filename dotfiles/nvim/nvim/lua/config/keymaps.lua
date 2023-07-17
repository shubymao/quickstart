-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local mark = require("harpoon.mark")
local ui = require("harpoon.ui")

vim.keymap.set("n", "<leader>a", mark.add_file, { desc = "add current file to harpoon" })
vim.keymap.set("n", "<leader>h", ui.toggle_quick_menu, { desc = "toggle harpoon quick menu" })

vim.keymap.set("n", "<leader>1", function()
  ui.nav_file(1)
end, { desc = "Switch to first harpoon" })
vim.keymap.set("n", "<leader>2", function()
  ui.nav_file(2)
end, { desc = "Switch to second harpoon" })
vim.keymap.set("n", "<leader>3", function()
  ui.nav_file(3)
end, { desc = "Switch to third harpoon" })
vim.keymap.set("n", "<leader>4", function()
  ui.nav_file(4)
end, { desc = "Switch to forth harpoon" })
