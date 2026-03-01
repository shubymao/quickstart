return {
  -- 1. Compatibility layer for nvim-cmp sources (like cmp-spell)
  {
    "saghen/blink.compat",
    version = "*",
    lazy = true,
    opts = {},
  },

  -- 2. Main Blink Configuration
  {
    "saghen/blink.cmp",
    version = "*",
    dependencies = { "f3fora/cmp-spell" },

    ---@module 'blink.cmp'
    ---@type blink.Config
    opts = {
      keymap = {
        preset = "default",
      },

      -- Fix for potential 'ipairs' errors in cmdline mode
      completion = {
        menu = { auto_show = true },
        ghost_text = { enabled = true },
      },

      -- Your custom sources
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "spell" },
        providers = {
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
    },
    -- This ensures our opts are merged correctly with LazyVim's
    opts_extend = { "sources.default" },
  },
}
