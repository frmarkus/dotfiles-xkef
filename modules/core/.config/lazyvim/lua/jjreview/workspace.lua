-- jj workspaces, one tab each. A tab belongs to the workspace its :tcd
-- names, so LSP roots, pickers, neo-tree, and jj commands follow the tab.
-- New workspaces go next to the default one, in ../<repo>.ws/<name>.
local jj = require("jjreview.jj")

local M = {}

local ADD = "+ Add workspace"
local REMOVE = "- Remove workspace"

local TEMPLATE = 'name ++ "\t" ++ root ++ "\t" ++ target.change_id().shortest(8) ++ " "'
  .. ' ++ coalesce(target.description().first_line(), "(no description)") ++ "\n"'

local function list()
  local out = jj.run({ "workspace", "list", "-T", TEMPLATE })
  local workspaces = {}
  for line in (out or ""):gmatch("[^\n]+") do
    local name, root, summary = line:match("^(.-)\t(.-)\t(.*)$")
    table.insert(workspaces, { name = name, root = root, summary = summary })
  end
  return workspaces
end

local function tab_of(root)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tab)) == root then
      return tab
    end
  end
end

-- Focuses the workspace's tab, or opens one there with the current file
-- when the workspace has it.
local function switch(workspace)
  local tab = tab_of(workspace.root)
  if tab then
    vim.api.nvim_set_current_tabpage(tab)
    return
  end

  local root = jj.root()
  local rel = root and vim.fs.relpath(root, vim.api.nvim_buf_get_name(0))
  vim.cmd.tabnew()
  vim.cmd.tcd(vim.fn.fnameescape(workspace.root))
  local file = rel and vim.fs.joinpath(workspace.root, rel)
  if file and vim.uv.fs_stat(file) then
    vim.cmd.edit(vim.fn.fnameescape(file))
  end
end

-- Items are workspaces or action labels.
local function pick(prompt, items, on_choice)
  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      if type(item) == "string" then
        return item
      end
      return ("%-16s %s  %s"):format(item.name, item.summary, vim.fn.fnamemodify(item.root, ":~"))
    end,
  }, function(item)
    if item then
      on_choice(item)
    end
  end)
end

-- Adds a workspace whose working copy starts on the revision selected in
-- the review panel, or on @.
local function add()
  local workspaces = list()
  if #workspaces == 0 then
    return
  end

  local main = workspaces[1]
  for _, ws in ipairs(workspaces) do
    if ws.name == "default" then
      main = ws
    end
  end

  vim.ui.input({ prompt = "New workspace name: " }, function(name)
    if not name or name == "" then
      return
    end
    local root = vim.fs.joinpath(vim.fs.dirname(main.root), vim.fs.basename(main.root) .. ".ws", name)
    local rev = require("jjreview.panel").selected() or "@"
    vim.fn.mkdir(vim.fs.dirname(root), "p")
    if jj.run({ "workspace", "add", "--name", name, "-r", rev, root }) then
      switch({ name = name, root = root })
    end
  end)
end

-- Deletes a workspace and its files, after the user confirms, and closes
-- its tab.
local function remove()
  local others = vim.tbl_filter(function(ws)
    return ws.name ~= "default"
  end, list())

  pick("Remove jj workspace", others, function(ws)
    local prompt = ("Delete workspace %s and the files in %s?"):format(ws.name, ws.root)
    if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
      return
    end
    local tab = tab_of(ws.root)
    if tab then
      vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(tab))
    end
    jj.run({ "workspace", "remove", ws.name })
  end)
end

-- Switches to a workspace, or adds or removes one.
function M.pick()
  local items = vim.list_extend(list(), { ADD, REMOVE })
  pick("jj workspace", items, function(item)
    if item == ADD then
      add()
    elseif item == REMOVE then
      remove()
    else
      switch(item)
    end
  end)
end

return M
