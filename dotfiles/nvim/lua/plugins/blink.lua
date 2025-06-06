return {
  {
    "saghen/blink.compat",
    -- use the latest release, via version = '*', if you also use the latest release for blink.cmp
    version = "*",
    -- lazy.nvim will automatically load the plugin when it's required by blink.cmp
    lazy = true,
    -- make sure to set opts so that lazy.nvim calls blink.compat's setup
    opts = {},
  },
  {
    "saghen/blink.cmp",
    version = "0.*",
    dependencies = { { "f3fora/cmp-spell" } },
    opts = {
      sources = {
        default = { "lsp", "path", "snippets", "buffer", "spell" },
        providers = {
          -- create provider
          spell = {
            -- IMPORTANT: use the same name as you would for nvim-cmp
            name = "spell",
            module = "blink.compat.source",

            -- all blink.cmp source config options work as normal:
            score_offset = -3,

            -- this table is passed directly to the proxied completion source
            -- as the `option` field in nvim-cmp's source config
            --
            -- this is NOT the same as the opts in a plugin's lazy.nvim spec
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
  },
}
