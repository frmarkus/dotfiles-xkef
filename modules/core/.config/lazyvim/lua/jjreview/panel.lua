-- The review panel of a tab: the log (log.lua) above neo-tree's jj source
-- on the left, the editor on the right. The tree lists the files of the
-- marked changes, or of the change under the cursor without marks.
--
--   ┌ revset trunk()..@ ┬ editor ─────────────────┐
--   │ @  wxyz  wip      │ @: the file on disk     │
--   │ ●  kpqx  auth     │ else: jj://REV/PATH     │
--   ├ files ────────────┤ signs against the parent│
--   │  M a.lua          │ of the oldest change    │
--   └───────────────────┴─────────────────────────┘
local jj = require("jjreview.jj")
local log = require("jjreview.log")

local M = {}

local DEFAULT_REVSET = "trunk()..@"
local PRESETS = {
  "trunk()..@",
  "mine() & mutable()",
  "trunk()..visible_heads()",
  "@ | @-",
  "conflicts()",
}
local CUSTOM = "Custom revset…"
local SELECT_DELAY_MS = 80
local DEFAULT_WIDTH = 40
local LOG_HEIGHT = 0.6

-- Panel state per tabpage: { root, revset, cursor, marks, rows,
-- log_buf, log_win, tree_win, files }. cursor and marks hold full change IDs.
local tabs = {}
local revset_history = {}
local gitdirs = {}

local function state()
  return tabs[vim.api.nvim_get_current_tabpage()]
end

function M.active()
  return state() ~= nil
end

function M.revset()
  local s = state()
  return s and s.revset or DEFAULT_REVSET
end

function M.selected()
  local s = state()
  return s and s.cursor
end

-- One entry per path across revisions given newest first. rev is the
-- newest revision that touches the path and base the oldest, so the
-- file shows as rev and diffs against base's parent.
local function combine(revs)
  local by_path, files = {}, {}
  for _, rev in ipairs(revs) do
    for _, f in ipairs(rev.files) do
      local entry = by_path[f.path]
      if not entry then
        entry = { path = f.path, status = f.status, rev = rev }
        by_path[f.path] = entry
        table.insert(files, entry)
      end
      entry.base, entry.base_status = rev, f.status
    end
  end

  for _, entry in ipairs(files) do
    if entry.base ~= entry.rev then
      if entry.base_status == "added" then
        entry.status = entry.status == "removed" and "modified" or "added"
      elseif entry.status ~= "removed" then
        entry.status = "modified"
      end
    end
  end
  table.sort(files, function(a, b)
    return a.path < b.path
  end)
  return files
end

-- The title and files of the selection. The tree calls this whenever it
-- renders.
function M.load()
  local s = state()
  local revset = "@"
  if s then
    local ids = vim.tbl_keys(s.marks)
    revset = #ids > 0 and table.concat(ids, " | ") or s.cursor or "@"
  end

  local revs = jj.revisions(revset)
  local files = combine(revs)
  if s then
    s.files = files
  end
  if #revs == 1 then
    return revs[1].change .. " " .. revs[1].title, files
  end
  return #revs .. " changes", files
end

local function refresh_tree()
  require("neo-tree.sources.manager").refresh("jj")
end

local select_token = 0

-- The selection changed: refresh the tree once the cursor rests.
function M.on_select()
  select_token = select_token + 1
  local token = select_token
  vim.defer_fn(function()
    if token == select_token and M.active() then
      refresh_tree()
    end
  end, SELECT_DELAY_MS)
end

local function reload_revision_buffers()
  vim.cmd.checktime()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.startswith(name, "jj://") and vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd.edit)
      end)
    end
  end
end

-- Runs after any jj operation, through the watcher or an action.
function M.on_change()
  reload_revision_buffers()
  local s = state()
  if not s then
    return
  end
  log.render(s)
  refresh_tree()
end

function M.set_revset(revset)
  local s = state()
  if not s then
    M.toggle(revset)
    return
  end
  table.insert(revset_history, 1, revset)
  s.revset = revset
  s.marks = {}
  log.render(s)
  refresh_tree()
end

function M.pick_revset()
  local items, seen = {}, {}
  for _, revset in ipairs(vim.list_extend(vim.list_slice(revset_history), PRESETS)) do
    if not seen[revset] then
      seen[revset] = true
      table.insert(items, revset)
    end
  end
  table.insert(items, CUSTOM)

  vim.ui.select(items, { prompt = "Revset (" .. M.revset() .. ")" }, function(choice)
    if choice == CUSTOM then
      vim.ui.input({ prompt = "Revset: ", default = M.revset() }, function(revset)
        if revset and revset ~= "" then
          M.set_revset(revset)
        end
      end)
    elseif choice then
      M.set_revset(choice)
    end
  end)
end

local function gitdir(root)
  if gitdirs[root] == nil then
    local out = vim.system({ "git", "-C", root, "rev-parse", "--absolute-git-dir" }, { text = true }):wait()
    gitdirs[root] = out.code == 0 and vim.trim(out.stdout) or false
  end
  return gitdirs[root] or nil
end

-- Points gitsigns at the commit of base, a revset. gitsigns can't find
-- the repo of a jj:// buffer, so the attach names it. A buffer gitsigns
-- attached already keeps its context and only changes its base.
local function signs(buf, root, path, base)
  local ok, gitsigns = pcall(require, "gitsigns")
  local dir, commit = gitdir(root), jj.commit(base)
  if not ok or not dir or not commit then
    return
  end

  local ctx = { file = vim.fs.joinpath(root, path), toplevel = root, gitdir = dir, base = commit }
  gitsigns.attach({ bufnr = buf, ctx = ctx }, function()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          gitsigns.change_base(commit)
        end)
      end
    end)
  end)
end

local function edit_revision(change, abs)
  local rel = vim.fs.relpath(vim.fn.getcwd(), abs) or abs
  vim.cmd.edit(vim.fn.fnameescape(("jj://%s/%s"):format(change, rel)))
end

-- Opens a file of the selection in the current window, after the split
-- command when given. A file of @ opens from disk. Any other revision
-- opens jj.nvim's jj:// buffer, which writes back to that revision. A
-- removed file shows the version before its removal.
function M.open(file, split)
  local root = jj.root()
  if not root then
    return
  end
  if split then
    vim.cmd(split)
  end

  local abs = vim.fs.joinpath(root, file.path)
  local base = file.base.id .. "-"
  if file.status == "removed" then
    edit_revision(jj.revisions(base)[1].change, abs)
    return
  end

  if file.rev.wc then
    vim.cmd.edit(vim.fn.fnameescape(abs))
  else
    edit_revision(file.rev.change, abs)
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].jjreview_base = base
  signs(buf, root, file.path, base)
end

-- Opens the file `step` places after `path` in the selection, skipping
-- removed files. Returns false at either end.
function M.adjacent(path, step)
  local s = state()
  if not s or not s.files then
    return false
  end

  local index = step > 0 and 0 or #s.files + 1
  for i, file in ipairs(s.files) do
    if file.path == path then
      index = i
    end
  end
  index = index + step
  while s.files[index] do
    local file = s.files[index]
    if file.status ~= "removed" then
      M.open(file)
      return true
    end
    index = index + step
  end
  return false
end

-- The revset and the number of marks, for the statusline.
function M.summary()
  local s = state()
  if not s then
    return ""
  end
  local count = vim.tbl_count(s.marks)
  return count > 0 and ("%s  %d marked"):format(s.revset, count) or s.revset
end

function M.focus_files()
  local s = state()
  if s and s.tree_win and vim.api.nvim_win_is_valid(s.tree_win) then
    vim.api.nvim_set_current_win(s.tree_win)
  end
end

local function close(tab)
  local s = tabs[tab]
  tabs[tab] = nil
  for _, win in ipairs({ s.tree_win, s.log_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  if s.log_buf and vim.api.nvim_buf_is_valid(s.log_buf) then
    vim.api.nvim_buf_delete(s.log_buf, { force = true })
  end
end

-- The panel and neo-tree share the left sidebar, one at a time. A neo-tree
-- window other than the panel's own tree closes the panel.
function M.on_neotree_open(args)
  local s = tabs[args.tabid]
  if not s or args.winid == s.tree_win then
    return
  end
  vim.schedule(function()
    if tabs[args.tabid] == s then
      close(args.tabid)
    end
  end)
end

-- Opens the sidebar in neo-tree's place and width: the log at the far
-- left, the tree below it.
function M.toggle(revset)
  local tab = vim.api.nvim_get_current_tabpage()
  if tabs[tab] then
    close(tab)
    return
  end

  local root = jj.root()
  if not root then
    jj.notify("Not in a jj workspace", vim.log.levels.WARN)
    return
  end
  local s = { root = root, revset = revset or DEFAULT_REVSET, marks = {}, rows = {} }
  tabs[tab] = s
  require("jjreview.watch").start(root, M.on_change)
  require("neo-tree.sources.manager").close_all()

  log.create(s)
  vim.cmd("topleft vsplit")
  local log_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(log_win, s.log_buf)
  vim.cmd("belowright split")
  s.tree_win = vim.api.nvim_get_current_win()
  require("neo-tree.command").execute({ source = "jj", position = "current", dir = root })

  -- The tree split copied the log window's options, so these come after.
  -- The log takes neo-tree's window highlights, so the sidebar has one
  -- background, separator, and statusline.
  log.setup_win(s, log_win)
  vim.wo[log_win].winhighlight = vim.wo[s.tree_win].winhighlight
  vim.wo[s.tree_win].winfixwidth = true
  local width = require("neo-tree").config.window.width
  vim.api.nvim_win_set_width(log_win, type(width) == "number" and width or DEFAULT_WIDTH)
  vim.api.nvim_win_set_height(log_win, math.floor((vim.o.lines - vim.o.cmdheight) * LOG_HEIGHT))

  log.render(s)
  vim.api.nvim_set_current_win(log_win)
end

local preview_token = 0
local preview_buf

-- Keeps a buffer that a preview opened, as if opened on purpose.
function M.keep(buf)
  if vim.b[buf].jjreview_preview then
    vim.b[buf].jjreview_preview = nil
    vim.bo[buf].buflisted = true
  end
end

-- Opens a file in win as a preview. A buffer the preview creates stays
-- unlisted, and the next preview wipes it unless it was kept, modified,
-- or shown elsewhere.
local function open_preview(win, file)
  local listed = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    listed[buf] = vim.bo[buf].buflisted or nil
  end
  vim.api.nvim_win_call(win, function()
    pcall(M.open, file)
  end)

  local buf = vim.api.nvim_win_get_buf(win)
  local old = preview_buf
  preview_buf = nil
  if not listed[buf] then
    vim.b[buf].jjreview_preview = true
    vim.bo[buf].buflisted = false
    preview_buf = buf
  end
  if
    old
    and old ~= buf
    and vim.api.nvim_buf_is_valid(old)
    and vim.b[old].jjreview_preview
    and not vim.bo[old].modified
    and #vim.fn.win_findbuf(old) == 0
  then
    vim.api.nvim_buf_delete(old, {})
  end
end

-- Preview mode: the file under the cursor in the tree opens in the editor
-- window once the cursor rests, and focus stays in the tree, so j and k
-- cycle through the files.
local function preview()
  local s = state()
  if not s or vim.api.nvim_get_current_win() ~= s.tree_win then
    return
  end

  preview_token = preview_token + 1
  local token = preview_token
  vim.defer_fn(function()
    if token ~= preview_token or vim.api.nvim_get_current_win() ~= s.tree_win then
      return
    end
    local tree = require("neo-tree.sources.manager").get_state("jj", nil, s.tree_win)
    local node = tree.tree and tree.tree:get_node()
    if not node or node.type ~= "file" then
      return
    end
    local win, is_tree = require("neo-tree.utils").get_appropriate_window(tree, true)
    if is_tree then
      return
    end
    open_preview(win, node.extra.jj_file)
  end, SELECT_DELAY_MS)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("jjreview_panel", { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", { group = group, callback = preview })

  -- Entering or editing a previewed buffer keeps it.
  vim.api.nvim_create_autocmd({ "WinEnter", "InsertEnter", "TextChanged" }, {
    group = group,
    callback = function(ev)
      M.keep(ev.buf)
    end,
  })

  -- The watcher refreshes the current tab only, so a tab catches up on
  -- entry.
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      local s = state()
      if s then
        log.render(s)
        refresh_tree()
      end
    end,
  })

  -- The panel follows its tab into another workspace, and closes when
  -- the tab leaves jj.
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      local s = state()
      local root = jj.root()
      if not s or root == s.root then
        return
      end
      if not root then
        close(vim.api.nvim_get_current_tabpage())
        return
      end
      require("jjreview.watch").start(root, M.on_change)
      s.root, s.marks, s.cursor = root, {}, nil
      log.render(s)
      refresh_tree()
    end,
  })

  -- Closing the log or the tree closes the whole panel.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      for tab, s in pairs(tabs) do
        if win == s.log_win or win == s.tree_win then
          vim.schedule(function()
            if tabs[tab] == s then
              close(tab)
            end
          end)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab in pairs(tabs) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          tabs[tab] = nil
        end
      end
    end,
  })
end

return M
