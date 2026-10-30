-- The log of the review panel: a special buffer with jj's graph, drawn
-- from a template so each line maps to its change. Marks select several
-- changes, the winbar shows the revset, and ? lists the keys.
local jj = require("jjreview.jj")

local M = {}

local FILETYPE = "jjreview_log"
local NS = vim.api.nvim_create_namespace("jjreview_log")
local MARK_SIGN = "●"
local DESCRIBE_HEIGHT = 10

-- Each change takes two lines, as in jjui, so the graph connects them.
-- The header starts with \30 after the graph, and \31 separates its
-- fields: full ID, unique prefix, rest of the short ID, working copy,
-- flags (immutable, conflict, empty), bookmarks, other workspaces, and
-- the age. The second line starts with \29 and holds the subject.
local TEMPLATE = '"\\x1e" ++ '
  .. table.concat({
    "change_id",
    "change_id.shortest(8).prefix()",
    "change_id.shortest(8).rest()",
    'if(current_working_copy, "@")',
    'if(immutable, "i") ++ if(conflict, "c") ++ if(empty, "e")',
    'bookmarks.join(" ")',
    'working_copies.join(" ")',
    "committer.timestamp().ago()",
  }, ' ++ "\\x1f" ++ ')
  .. ' ++ "\\n\\x1d" ++ description.first_line() ++ "\\n"'

local HIGHLIGHTS = {
  JJReviewPrefix = { link = "Identifier" },
  JJReviewRest = { link = "Comment" },
  JJReviewBookmark = { link = "Constant" },
  JJReviewWorkspace = { link = "Special" },
  JJReviewSubject = { link = "Normal" },
  JJReviewQuiet = { link = "Comment" },
  JJReviewConflict = { link = "DiagnosticError" },
  JJReviewWorkingCopy = { link = "DiagnosticOk" },
  JJReviewMarked = { link = "Visual" },
  JJReviewMarkSign = { link = "DiagnosticWarn" },
  JJReviewRevsetLabel = { link = "Title" },
  JJReviewRevset = { link = "String" },
  JJReviewHiddenCursor = { blend = 100, nocombine = true },
}

-- Actions run on the targets: the marked changes, or the change under the
-- cursor without marks. Each key appears in the help in this order.
local KEYS = {
  { "j", "next", "Next change" },
  { "k", "prev", "Previous change" },
  { "gg", "first", "First change" },
  { "G", "last", "Last change" },
  { "<Space>", "toggle_mark", "Mark or unmark changes", { "n", "x" } },
  { "M", "clear_marks", "Clear the marks" },
  { "<CR>", "edit", "Edit the change: move @ there" },
  { "n", "new", "New change on the targets (several make a merge)" },
  { "a", "new_after", "Insert a new change after the change" },
  { "b", "new_before", "Insert a new change before the change" },
  { "d", "describe", "Edit the description of the change" },
  { "s", "squash", "Squash the targets into their parent" },
  { "S", "squash_into", "Squash the marked changes into the change" },
  { "r", "rebase_onto", "Rebase the marked changes onto the change" },
  { "A", "rebase_after", "Move the marked changes after the change" },
  { "B", "rebase_before", "Move the marked changes before the change" },
  { "J", "move_down", "Swap the change with its parent" },
  { "K", "move_up", "Swap the change with its child" },
  { "x", "abandon", "Abandon the targets" },
  { "gb", "bookmark", "Set a bookmark on the change" },
  { "u", "undo", "Undo the last jj operation" },
  { "<C-r>", "redo", "Redo the last undone operation" },
  { "/", "revset", "Pick or edit the revset" },
  { "D", "diff", "Open the targets in diffview" },
  { "y", "yank", "Copy the change ID" },
  { "R", "refresh", "Refresh" },
  { "<Tab>", "files", "Focus the files" },
  { "q", "close", "Close the panel" },
  { "?", "help", "Show this help" },
}

local function panel()
  return require("jjreview.panel")
end

-- Builds a line from graph and parts, with the highlight of each part.
-- Parts are space-separated unless glued to the one before.
local function line(graph, parts)
  local text, hls = graph, {}
  for _, part in ipairs(parts) do
    local s, hl = part[1], part[2]
    if s ~= "" then
      if #text > #graph and not part.glue then
        text = text .. " "
      end
      table.insert(hls, { #text, #text + #s, hl })
      text = text .. s
    end
  end
  return text, hls
end

-- Parses jj's output into display lines. rows maps each header line to
-- its change, and owners maps both lines of a change to it.
local function parse(out)
  local lines, rows, owners, hls = {}, {}, {}, {}
  local rev
  for raw in out:gmatch("[^\n]*") do
    local graph, rest = raw:match("^(.-)\30(.*)$")
    local body_graph, subject = raw:match("^(.-)\29(.*)$")
    if graph then
      local f = vim.split(rest, "\31", { plain = true })
      rev = {
        id = f[1],
        prefix = f[2],
        rest = f[3],
        wc = f[4] == "@",
        immutable = f[5]:find("i") ~= nil,
        conflict = f[5]:find("c") ~= nil,
        empty = f[5]:find("e") ~= nil,
      }
      local text, line_hls = line(graph, {
        { rev.prefix, "JJReviewPrefix" },
        { rev.rest, "JJReviewRest", glue = true },
        { f[6], "JJReviewBookmark" },
        { f[7], "JJReviewWorkspace" },
        { rev.conflict and "conflict" or "", "JJReviewConflict" },
        { f[8], "JJReviewQuiet" },
      })
      if rev.wc and graph:find("@", 1, true) then
        local at = graph:find("@", 1, true)
        table.insert(line_hls, { at - 1, at, "JJReviewWorkingCopy" })
      end
      table.insert(lines, text)
      rows[#lines], owners[#lines], hls[#lines] = rev, rev, line_hls
    elseif body_graph and rev then
      local quiet = (subject == "" or rev.immutable) and "JJReviewQuiet" or "JJReviewSubject"
      if subject == "" then
        subject = rev.empty and "(empty)" or "(no description)"
      end
      local text, line_hls = line(body_graph, { { subject, quiet } })
      table.insert(lines, text)
      owners[#lines], hls[#lines] = rev, line_hls
    elseif raw ~= "" then
      table.insert(lines, raw)
    end
  end

  -- The graph ends in a connector and jj's "~" for elided ancestors,
  -- which read as Vim's end-of-buffer filler.
  while #lines > 0 and not owners[#lines] do
    table.remove(lines)
  end
  return lines, rows, owners, hls
end

local function winbar(revset)
  return "%#JJReviewRevsetLabel# revset %#JJReviewRevset#" .. revset:gsub("%%", "%%%%") .. "%=%#Comment#/ edit  ? help "
end

-- Redraws the log of state s, keeping the cursor on the same change.
function M.render(s)
  local buf = s.log_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local args = { "log", "-r", s.revset, "-T", TEMPLATE }
  local out = jj.run(args, { silent = true })
  local lines, rows, owners, hls = parse(out or "")
  if not out then
    lines = { "  invalid revset" }
  end
  s.rows = rows

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for lnum, line_hls in pairs(hls) do
    for _, hl in ipairs(line_hls) do
      vim.api.nvim_buf_set_extmark(buf, NS, lnum - 1, hl[1], { end_col = hl[2], hl_group = hl[3] })
    end
    if s.marks[owners[lnum].id] then
      vim.api.nvim_buf_set_extmark(buf, NS, lnum - 1, 0, {
        line_hl_group = "JJReviewMarked",
        sign_text = MARK_SIGN,
        sign_hl_group = "JJReviewMarkSign",
      })
    end
  end

  local win = s.log_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = winbar(s.revset)
    for lnum, rev in pairs(rows) do
      if rev.id == s.cursor then
        vim.api.nvim_win_set_cursor(win, { lnum, 0 })
      end
    end
  end
end

-- The change on a line, or on the nearest line above it that has one.
local function rev_at(s, lnum)
  for l = lnum, 1, -1 do
    if s.rows[l] then
      return s.rows[l]
    end
  end
end

local function cursor_rev(s)
  return rev_at(s, vim.api.nvim_win_get_cursor(0)[1])
end

-- Marked change IDs in log order, newest first.
local function marked(s)
  local ids = {}
  for lnum = 1, vim.api.nvim_buf_line_count(s.log_buf) do
    local rev = s.rows[lnum]
    if rev and s.marks[rev.id] then
      table.insert(ids, rev.id)
    end
  end
  return ids
end

local function targets(s)
  local ids = marked(s)
  if #ids == 0 then
    local rev = cursor_rev(s)
    return rev and { rev.id } or {}
  end
  return ids
end

local function union(ids)
  return table.concat(ids, " | ")
end

-- Runs jj, then clears the marks and refreshes the panel on success.
local function run(s, args, opts)
  if not jj.run(args, opts) then
    return
  end
  s.marks = {}
  panel().on_change()
end

local function need_marks(s)
  local ids = marked(s)
  if #ids == 0 then
    jj.notify("Mark changes first with <Space>", vim.log.levels.WARN)
    return nil
  end
  return ids
end

-- Edits a description in the sidebar, in a window above the files.
local function describe(s, rev)
  local text = jj.run({ "log", "-r", rev.id, "--no-graph", "-T", "description" }) or ""
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "jjreview://describe/" .. rev.prefix .. rev.rest)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text:gsub("\n$", ""), "\n"))
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "jjdescription"

  local win = vim.api.nvim_open_win(buf, true, { split = "above", win = s.tree_win, height = DESCRIBE_HEIGHT })
  vim.wo[win].winhighlight = vim.wo[s.log_win].winhighlight
  vim.wo[win].winfixbuf = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  vim.wo[win].winbar = "%#JJReviewRevsetLabel# describe %#JJReviewPrefix#"
    .. rev.prefix
    .. rev.rest
    .. "%=%#Comment#:w save  q cancel "

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local message = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
      if jj.run({ "describe", "-r", rev.id, "--stdin" }, { stdin = message }) then
        vim.bo[buf].modified = false
        vim.api.nvim_win_close(win, true)
        panel().on_change()
      end
    end,
  })
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

local function help()
  local lines = {}
  for _, key in ipairs(KEYS) do
    table.insert(lines, (" %-8s %s "):format(key[1], key[3]))
  end
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " jj log keys ",
  })
  for _, key in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      pcall(vim.api.nvim_win_close, win, true)
    end,
  })
end

local actions = {}

-- Moves the cursor to the next change line in a direction, from the
-- cursor or from an edge, so it never rests on a graph-only line.
local function step(s, from, direction)
  local lnum = from + direction
  while lnum >= 1 and lnum <= vim.api.nvim_buf_line_count(s.log_buf) do
    if s.rows[lnum] then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return
    end
    lnum = lnum + direction
  end
end

function actions.next(s)
  step(s, vim.fn.line("."), 1)
end

function actions.prev(s)
  step(s, vim.fn.line("."), -1)
end

function actions.first(s)
  step(s, 0, 1)
end

function actions.last(s)
  step(s, vim.api.nvim_buf_line_count(s.log_buf) + 1, -1)
end

function actions.toggle_mark(s)
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  local visual = vim.fn.mode():find("^[vV]") ~= nil
  if visual then
    vim.cmd("normal! \27")
  end

  -- Each change spans two lines, so a range toggles each change once.
  local seen = {}
  for lnum = math.min(first, last), math.max(first, last) do
    local rev = rev_at(s, lnum)
    if rev and not seen[rev.id] then
      seen[rev.id] = true
      s.marks[rev.id] = (not s.marks[rev.id]) or nil
    end
  end
  if not visual then
    actions.next(s)
  end
  M.render(s)
  panel().on_select()
end

function actions.clear_marks(s)
  s.marks = {}
  M.render(s)
  panel().on_select()
end

function actions.edit(s)
  run(s, { "edit", cursor_rev(s).id })
end

function actions.new(s)
  run(s, vim.list_extend({ "new" }, targets(s)))
end

function actions.new_after(s)
  run(s, { "new", "--insert-after", cursor_rev(s).id })
end

function actions.new_before(s)
  run(s, { "new", "--insert-before", cursor_rev(s).id })
end

function actions.describe(s)
  describe(s, cursor_rev(s))
end

-- Squashes keep the destination's description, so jj never asks for a
-- combined one. d edits it afterwards.
function actions.squash(s)
  for _, id in ipairs(targets(s)) do
    if not jj.run({ "squash", "-r", id, "--use-destination-message" }) then
      break
    end
  end
  s.marks = {}
  panel().on_change()
end

function actions.squash_into(s)
  local ids = need_marks(s)
  if ids then
    run(s, { "squash", "--from", union(ids), "--into", cursor_rev(s).id, "--use-destination-message" })
  end
end

local function rebase(flag)
  return function(s)
    local ids = need_marks(s)
    if ids then
      run(s, { "rebase", "-r", union(ids), flag, cursor_rev(s).id })
    end
  end
end

actions.rebase_onto = rebase("--onto")
actions.rebase_after = rebase("--insert-after")
actions.rebase_before = rebase("--insert-before")

function actions.move_down(s)
  local id = cursor_rev(s).id
  run(s, { "rebase", "-r", id, "--insert-before", id .. "-" })
end

function actions.move_up(s)
  local id = cursor_rev(s).id
  run(s, { "rebase", "-r", id, "--insert-after", id .. "+" })
end

function actions.abandon(s)
  local ids = targets(s)
  if vim.fn.confirm(("Abandon %d change(s)?"):format(#ids), "&Yes\n&No", 2) == 1 then
    run(s, { "abandon", union(ids) })
  end
end

function actions.bookmark(s)
  local rev = cursor_rev(s)
  vim.ui.input({ prompt = "Bookmark: " }, function(name)
    if name and name ~= "" then
      run(s, { "bookmark", "set", name, "-r", rev.id, "--allow-backwards" })
    end
  end)
end

function actions.undo(s)
  run(s, { "undo" })
end

function actions.redo(s)
  run(s, { "redo" })
end

function actions.revset()
  panel().pick_revset()
end

function actions.diff(s)
  local ids = targets(s)
  local revset = union(ids)
  local from = jj.commit(("roots(%s)-"):format(revset))
  local to = jj.commit(("heads(%s)"):format(revset))
  if from and to then
    vim.cmd(("DiffviewOpen %s..%s"):format(from, to))
  end
end

function actions.yank(s)
  local id = cursor_rev(s).id
  vim.fn.setreg("+", id)
  jj.notify("Copied " .. id)
end

function actions.refresh()
  panel().on_change()
end

function actions.files()
  panel().focus_files()
end

function actions.close()
  panel().toggle()
end

function actions.help()
  help()
end

-- Creates the log buffer of state s with its keys.
function M.create(s)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = FILETYPE
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  s.log_buf = buf

  for name, value in pairs(HIGHLIGHTS) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", value, { default = true }))
  end

  for _, key in ipairs(KEYS) do
    local lhs, name, desc, modes = unpack(key)
    vim.keymap.set(modes or "n", lhs, function()
      actions[name](s)
    end, { buffer = buf, desc = desc, nowait = true })
  end

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      local rev = cursor_rev(s)
      if rev and rev.id ~= s.cursor then
        s.cursor = rev.id
        panel().on_select()
      end
    end,
  })

  -- The cursor hides in the log, as in neo-tree, and the cursor line
  -- shows the selection.
  local guicursor
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    buffer = buf,
    callback = function()
      guicursor = guicursor or vim.o.guicursor
      vim.o.guicursor = "a:JJReviewHiddenCursor"
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
    buffer = buf,
    callback = function()
      if guicursor then
        vim.o.guicursor, guicursor = guicursor, nil
      end
    end,
  })
  return buf
end

-- Window options for the log window.
function M.setup_win(s, win)
  s.log_win = win
  local wo = vim.wo[win]
  wo.number, wo.relativenumber = false, false
  wo.signcolumn = "yes:1"
  wo.cursorline = true
  wo.wrap = false
  wo.winfixbuf = true
  wo.winfixwidth = true
  wo.fillchars = "eob: "
  wo.list = false
  wo.winbar = winbar(s.revset)
end

return M
