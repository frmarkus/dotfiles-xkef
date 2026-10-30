-- jj.nvim plus lua/jjreview: a review panel, hunk moves between
-- revisions, and jj workspaces as tabs.
local function call(module, fn)
  return function()
    require(module)[fn]()
  end
end

local function hunk_keys(fn)
  return function()
    local first, last = vim.fn.line("v"), vim.fn.line(".")
    vim.cmd("normal! \27")
    require("jjreview.hunk")[fn](math.min(first, last), math.max(first, last))
  end
end

return {
  {
    "nicolasgb/jj.nvim",
    version = "*",
    dependencies = {
      "folke/snacks.nvim",
      "sindrets/diffview.nvim",
    },
    keys = {
      { "<leader>jd", "<cmd>Jdiff<cr>", desc = "jj diff" },
      { "<leader>jp", "<cmd>J push<cr>", desc = "jj push" },
      { "<leader>jf", "<cmd>J fetch<cr>", desc = "jj fetch" },
      { "<leader>jb", "<cmd>Jbrowse<cr>", mode = { "n", "x" }, desc = "jj browse" },
      { "<leader>ja", call("jj.annotate", "line"), desc = "jj annotate line" },
      { "<leader>jA", call("jj.annotate", "file"), desc = "jj annotate file" },
      { "<leader>jh", call("jj.picker", "file_history"), desc = "jj file history" },
      { "<leader>jc", call("jj.picker", "conflict"), desc = "jj conflicts" },
      { "<leader>jr", "<cmd>JReview<cr>", desc = "jj review" },
      { "<leader>jw", call("jjreview.workspace", "pick"), desc = "jj workspaces" },
      { "<leader>jm", hunk_keys("move"), mode = { "n", "x" }, desc = "jj move hunk" },
      { "<leader>jS", hunk_keys("split"), mode = { "n", "x" }, desc = "jj split hunk" },
    },
    cmd = { "J", "Jdiff", "Jhdiff", "Jbrowse", "JReview" },
    opts = {
      diff = { backend = "diffview" },
    },
    config = function(_, opts)
      require("jj").setup(opts)
      require("jjreview").setup()
    end,
  },

  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>j", group = "jj", icon = { cat = "filetype", name = "git" } })
    end,
  },

  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = function(_, opts)
      opts.sources = opts.sources or { "filesystem", "buffers", "git_status" }
      table.insert(opts.sources, "jjreview.neotree")
      opts.event_handlers = opts.event_handlers or {}
      table.insert(opts.event_handlers, {
        event = "neo_tree_window_after_open",
        handler = function(args)
          require("jjreview.panel").on_neotree_open(args)
        end,
      })
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      opts.extensions = opts.extensions or {}
      table.insert(opts.extensions, require("jjreview.lualine"))
    end,
  },

  -- ]h and [h cross into the next file while the review panel is open.
  {
    "lewis6991/gitsigns.nvim",
    opts = function(_, opts)
      local attach = opts.on_attach
      opts.on_attach = function(buf)
        attach(buf)
        for key, direction in pairs({ ["]h"] = "next", ["[h"] = "prev" }) do
          vim.keymap.set("n", key, function()
            require("jjreview.hunk").nav(direction)
          end, { buffer = buf, desc = direction == "next" and "Next Hunk" or "Prev Hunk" })
        end
      end
    end,
  },

  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  },

  {
    "julienvincent/hunk.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    cmd = { "DiffEditor" },
    opts = {},
  },
}
