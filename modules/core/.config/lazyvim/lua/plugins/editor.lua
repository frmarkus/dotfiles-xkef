-- Marks the pane as running Neovim, as smart-splits does when it loads:
-- tmux's @pane-is-vim, or WezTerm's IS_NVIM user var. The tmux and WezTerm
-- leader h/j/k/l read the mark to hand the key to Neovim. The plugin loads
-- on its first key, so the mark can't wait for it, and its blocking tmux
-- calls cost about 22 ms at startup, so tmux runs in the background here.
-- A Neovim nested in a pane that already has the mark leaves it to the
-- outer one, as the plugin does. The plugin, once loaded, sees the mark and
-- treats itself as nested, so the reset on exit stays here.
local function tmux(args, opts, on_exit)
  local cmd = { "tmux", "-S", vim.split(vim.env.TMUX, ",")[1] }
  return vim.system(vim.list_extend(cmd, args), opts, on_exit)
end

local function set_mark(on)
  if vim.env.TERM_PROGRAM == "tmux" then
    tmux({ "set-option", "-pt", vim.env.TMUX_PANE, "@pane-is-vim", on and "1" or "0" }, { detach = true })
    return
  end

  local value = vim.base64.encode(on and "true" or "false")
  vim.api.nvim_chan_send(vim.v.stderr, "\027]1337;SetUserVar=IS_NVIM=" .. value .. "\007")
end

local function own_mark()
  set_mark(true)
  local group = vim.api.nvim_create_augroup("mux_pane_mark", { clear = true })
  vim.api.nvim_create_autocmd("VimResume", {
    group = group,
    callback = function()
      set_mark(true)
    end,
  })
  vim.api.nvim_create_autocmd({ "VimSuspend", "VimLeavePre" }, {
    group = group,
    callback = function()
      set_mark(false)
    end,
  })
end

local function mark_pane()
  local ui = vim.api.nvim_list_uis()[1]
  if not (ui and ui.stdout_tty) then
    return
  end

  local term = vim.env.TERM_PROGRAM
  if term == "WezTerm" then
    own_mark()
  elseif term == "tmux" and vim.env.TMUX and vim.env.TMUX_PANE then
    tmux({ "show-options", "-pqvt", vim.env.TMUX_PANE, "@pane-is-vim" }, { text = true }, function(out)
      if vim.trim(out.stdout or "") ~= "1" then
        vim.schedule(own_mark)
      end
    end)
  end
end

return {
  {
    "mrjones2014/smart-splits.nvim",
    -- v3 moved the WezTerm and tmux support into separate backend plugins,
    -- and the WezTerm one is still unstable. v2 ships both.
    tag = "v2.1.1-final",
    init = function()
      vim.api.nvim_create_autocmd("UIEnter", { once = true, callback = mark_pane })
    end,
    -- Resizes by the same 5 cells as the tmux and WezTerm leader H/J/K/L.
    opts = { default_amount = 5 },
    keys = (function()
      local ss = "smart-splits"
      local keys = {}
      for _, m in ipairs({
        { "<C-h>", "move_cursor_left" },
        { "<C-j>", "move_cursor_down" },
        { "<C-k>", "move_cursor_up" },
        -- macOS takes Ctrl-arrows for Spaces, so LazyVim's resize keys never
        -- reach Neovim.
        { "<A-H>", "resize_left" },
        { "<A-J>", "resize_down" },
        { "<A-K>", "resize_up" },
        { "<A-L>", "resize_right" },
      }) do
        keys[#keys + 1] = {
          m[1],
          function()
            require(ss)[m[2]]()
          end,
        }
      end

      -- Clears multicursors while any exist, as the default CTRL-L mapping
      -- does (:h CTRL-L-default). Otherwise the key moves right like its
      -- siblings.
      local mc_ns = vim.api.nvim_create_namespace("nvim.multicursor")
      keys[#keys + 1] = {
        "<C-l>",
        function()
          if next(vim.api.nvim_buf_get_extmarks(0, mc_ns, 0, -1, { limit = 1 })) then
            vim.api.nvim_buf_clear_namespace(0, mc_ns, 0, -1)
            return
          end

          require(ss).move_cursor_right()
        end,
      }
      return keys
    end)(),
  },

  -- Collapses the harpoon2 extra's <leader>1-9 into one which-key row. The
  -- hidden keys still work.
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>1", desc = "Harpoon to File 1-9" })
      for i = 2, 9 do
        table.insert(opts.spec, { "<leader>" .. i, hidden = true })
      end
    end,
  },

  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          files = { hidden = true },
          grep = { hidden = true },
        },
      },
    },
    init = function()
      -- Hide hunk headers in the Snacks diff renderer.
      local ok, diff = pcall(require, "snacks.picker.util.diff")
      if ok and diff.render then
        local orig = diff.render
        diff.render = function(buf, ns, d, opts)
          opts = vim.tbl_deep_extend("force", opts or {}, { hunk_header = false })
          return orig(buf, ns, d, opts)
        end
      end
    end,
  },
}
