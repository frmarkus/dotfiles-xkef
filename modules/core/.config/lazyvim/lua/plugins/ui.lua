-- In a jj repo the statusline shows the working-copy change ID and its
-- bookmarks instead of the git branch, which is a detached HEAD there.
-- jj runs in the background with --ignore-working-copy, so it never
-- snapshots or blocks the editor.
local JJ_TEMPLATE = 'separate(" ", change_id.shortest(8), bookmarks.join(" "))'
local jj_status = {}

local function jj_root()
  return vim.fs.root(0, ".jj")
end

local function jj_refresh()
  local root = jj_root()
  if not root then
    return
  end

  local cmd = { "jj", "log", "-r", "@", "--no-graph", "--ignore-working-copy", "--color", "never", "-T", JJ_TEMPLATE }
  vim.system(cmd, { cwd = root, text = true }, function(out)
    if out.code ~= 0 then
      return
    end
    jj_status[root] = vim.trim(out.stdout)
    vim.schedule(function()
      require("lualine").refresh()
    end)
  end)
end

return {
  { "akinsho/bufferline.nvim", enabled = false },

  {
    "nvim-lualine/lualine.nvim",
    init = function()
      vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "DirChanged", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("lualine_jj", { clear = true }),
        callback = jj_refresh,
      })
    end,
    opts = {
      sections = {
        lualine_b = {
          {
            "branch",
            cond = function()
              return not jj_root()
            end,
          },
          {
            function()
              return "󰘬 " .. (jj_status[jj_root()] or "")
            end,
            cond = function()
              return jj_root() ~= nil
            end,
          },
        },
        lualine_y = {
          function()
            local height = vim.fn.line("$")
            local width = #tostring(height)
            return "ℓ " .. string.format("%" .. width .. "d/%d", vim.fn.line("."), height)
          end,
        },
        lualine_z = {
          function()
            return "𝚌" .. string.format(" %2d", vim.fn.virtcol("."))
          end,
        },
      },
    },
  },

  {
    "nvim-neo-tree/neo-tree.nvim",
    init = function()
      -- The tree's statusline runs under its separator column, so the
      -- separator takes the tree's background and hides its line to keep
      -- the sidebar flush.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("neotree_separator", { clear = true }),
        callback = function()
          local bg = vim.api.nvim_get_hl(0, { name = "NeoTreeNormal", link = false }).bg
          vim.api.nvim_set_hl(0, "NeoTreeWinSeparator", { fg = bg, bg = bg })
        end,
      })
    end,
    opts = function(_, opts)
      opts.filesystem = opts.filesystem or {}
      -- group_empty_dirs crashes nui when a second single-child chain
      -- expands: https://github.com/nvim-neo-tree/neo-tree.nvim/issues/2099
      opts.filesystem.group_empty_dirs = false
      local fi = opts.filesystem.filtered_items or {}
      fi.visible = true
      fi.hide_dotfiles = false
      fi.hide_hidden = false
      -- .classpath and its siblings are Eclipse metadata that jdtls writes.
      fi.never_show = { ".DS_Store", ".git", ".jj", ".idea", ".classpath", ".project", ".settings", ".factorypath" }
      opts.filesystem.filtered_items = fi

      -- A wide tree shows stat columns. Type and date say little, so they
      -- go, and the size column shows the line count instead. Counts are
      -- cached by mtime. Binary files and files over 1 MB show "-".
      opts.default_component_configs = opts.default_component_configs or {}
      opts.default_component_configs.type = { enabled = false }
      opts.default_component_configs.last_modified = { enabled = false }
      opts.default_component_configs.file_size = { width = 8 }
      local max_bytes = 1024 * 1024
      local loc_cache = {}
      local function count_lines(path)
        local stat = vim.uv.fs_stat(path)
        if not stat or stat.size > max_bytes then
          return nil
        end
        local cached = loc_cache[path]
        if cached and cached.mtime == stat.mtime.sec then
          return cached.lines
        end

        local f = io.open(path, "rb")
        if not f then
          return nil
        end
        local data = f:read("*a")
        f:close()
        local lines = nil
        if not data:find("\0", 1, true) then
          local _, n = data:gsub("\n", "")
          lines = n
        end
        loc_cache[path] = { mtime = stat.mtime.sec, lines = lines }
        return lines
      end
      opts.filesystem.components = opts.filesystem.components or {}
      opts.filesystem.components.file_size = function(config, node)
        local text = "-"
        if node:get_depth() == 1 then
          text = "Lines"
        elseif node.type == "file" then
          text = tostring(count_lines(node.path) or "-")
        end
        return {
          text = string.format("%" .. config.width .. "s  ", text),
          highlight = node:get_depth() == 1 and "NeoTreeFileStatsHeader" or "NeoTreeFileStats",
        }
      end

      -- Opening a directory keeps descending while it holds a single
      -- subdirectory, so l on java opens java/com/netcetera/deip at once.
      -- This replaces group_empty_dirs above.
      local function open_chain(state)
        local fs = require("neo-tree.sources.filesystem")
        local node = state.tree:get_node()
        if node.type ~= "directory" or node:is_expanded() then
          return require("neo-tree.sources.filesystem.commands").open(state)
        end

        local function descend(dir)
          local children = state.tree:get_nodes(dir:get_id())
          if #children ~= 1 or children[1].type ~= "directory" then
            return
          end
          local child = children[1]
          if child.loaded == false then
            fs.toggle_directory(state, child, nil, false, false, function()
              descend(state.tree:get_node(child:get_id()))
            end)
            return
          end
          child:expand()
          require("neo-tree.ui.renderer").redraw(state)
          descend(child)
        end

        if node.loaded ~= false then
          node:expand()
          require("neo-tree.ui.renderer").redraw(state)
          return descend(node)
        end
        fs.toggle_directory(state, node, nil, false, false, function()
          descend(state.tree:get_node(node:get_id()))
        end)
      end
      opts.filesystem.window = opts.filesystem.window or {}
      opts.filesystem.window.mappings = vim.tbl_extend("force", opts.filesystem.window.mappings or {}, {
        ["l"] = open_chain,
        ["<cr>"] = open_chain,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        ["<C-n>"] = { "show", "select_next", "fallback" },
        ["<C-p>"] = { "show", "select_prev", "fallback" },
      },
    },
  },
}
