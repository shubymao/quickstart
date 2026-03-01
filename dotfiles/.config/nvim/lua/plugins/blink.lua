return {
  -- 1. Setup the compatibility layer for nvim-cmp sources
  {
    "saghen/blink.compat",
    version = "*",
    lazy = true,
    opts = {},
  },

  -- 2. Setup the main completion engine
  {
    "saghen/blink.cmp",
    version = "*", -- Use latest to stay in sync with LazyVim updates
    dependencies = { "f3fora/cmp-spell" },

    opts = {
      keymap = {
        preset = "default",
        -- You can add custom keys here if you want (e.g. ['<Tab>'] = { 'select_next', 'fallback' })
      },

      -- Define your completion sources
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "spell" },
        providers = {
          -- Configure the 'spell' source via blink.compat
          spell = {
            name = "spell",
            module = "blink.compat.source",
            score_offset = -3,
            opts = {
              keep_all_entries = false,
              enable_in_context = function()
                return true
              end,
              preselect_correct_word = true,
            },
          },
        },
      },

      -- Optional: Enable ghost text (previewing the completion in gray)
      completion = {
        ghost_text = { enabled = true },
      },
    },
  },
}
