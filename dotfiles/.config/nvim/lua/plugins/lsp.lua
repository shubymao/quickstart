return {
  -- Use the new organization name
  "mason-org/mason.nvim",
  opts = function(_, opts)
    -- Ensure the list exists, then add your custom tools
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