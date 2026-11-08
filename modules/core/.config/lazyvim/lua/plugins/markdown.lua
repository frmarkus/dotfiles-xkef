-- Markdown without the LazyVim markdown extra, whose linter, formatters,
-- preview, and rendering this config doesn't use: marksman for links and
-- headings, rumdl for lint and format, and vale for prose. rumdl and vale
-- come from Homebrew or pacman, and a project's mise.toml can pin its own
-- versions through the mise shims. rumdl and vale run only in a project
-- with its own config. rumdl formats a file that the project's treefmt or
-- dprint config doesn't cover, as format.lua decides.

-- Both tools search for config from the working directory, not from the
-- file, so the linter passes the file's project config explicitly. The
-- dotfiles repo keeps its vale config at .config/vale/.vale.ini.
local project = require("project")

vim.filetype.add({ extension = { mdx = "markdown.mdx" } })

local VALE_CONFIGS = { ".vale.ini", "_vale.ini", ".config/vale/.vale.ini", ".config/vale/vale.ini" }
local RUMDL_CONFIGS = {
  ".rumdl.toml",
  "rumdl.toml",
  ".config/rumdl.toml",
  ".markdownlint.json",
  ".markdownlint.jsonc",
  ".markdownlint.yaml",
  ".markdownlint.yml",
  ".markdownlint-cli2.jsonc",
  ".markdownlint-cli2.yaml",
}

-- Linter overrides that skip files outside a configured project and point
-- the tool at the project config.
local function configured(names, args)
  return {
    condition = function(ctx)
      return project.config(ctx.filename, names) ~= nil
    end,
    prepend_args = vim.list_extend(args, {
      "--config",
      function()
        return (project.config(vim.api.nvim_buf_get_name(0), names))
      end,
    }),
  }
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { marksman = {} } },
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.markdown = { "rumdl", "vale" }
      opts.linters_by_ft["markdown.mdx"] = { "rumdl", "vale" }

      opts.linters = opts.linters or {}
      opts.linters.rumdl = configured(RUMDL_CONFIGS, {})

      -- nvim-lint reads rumdl's JSON from stderr, but rumdl writes it to
      -- stdout, so no rumdl diagnostic ever appeared.
      opts.linters.rumdl.stream = "stdout"

      -- vale merges the global config into a project config unless told
      -- not to.
      opts.linters.vale = configured(VALE_CONFIGS, { "--no-global" })
    end,
  },
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.markdown = { "rumdl" }
      opts.formatters_by_ft["markdown.mdx"] = { "rumdl" }

      opts.formatters = opts.formatters or {}
      opts.formatters.rumdl = {
        condition = function(_, ctx)
          return project.config(ctx.filename, RUMDL_CONFIGS) ~= nil
        end,
        args = function(_, ctx)
          local config = project.config(ctx.filename, RUMDL_CONFIGS)
          return { "fmt", "--config", config, "--stdin-filename", "$FILENAME", "-" }
        end,
      }
    end,
  },
}
