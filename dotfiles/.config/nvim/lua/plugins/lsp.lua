return {
  "williamboman/mason.nvim",
  opts = function(_, opts)
    -- This ensures your list is MERGED with LazyVim's defaults
    opts.ensure_installed = opts.ensure_installed or {}
    vim.list_extend(opts.ensure_installed, {
      "stylua",
      "shellcheck",
      "shfmt",
      "flake8",
      "codespell",
    })
  end,
}