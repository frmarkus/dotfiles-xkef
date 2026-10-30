-- Watches a repo's operation heads, which change whenever any jj process
-- commits an operation, an agent in another pane included. Workspaces
-- share one repo, so one watcher covers all of them.
local M = {}

local DEBOUNCE_MS = 150

local watchers = {}

-- A secondary workspace's .jj/repo is a file that holds the path of the
-- main workspace's repo directory, relative to its .jj directory.
local function repo_dir(root)
  local repo = vim.fs.joinpath(root, ".jj", "repo")
  local stat = vim.uv.fs_stat(repo)
  if not stat then
    return nil
  end
  if stat.type == "directory" then
    return vim.uv.fs_realpath(repo)
  end

  local target = vim.trim(vim.fn.readfile(repo)[1] or "")
  if not vim.startswith(target, "/") then
    target = vim.fs.joinpath(root, ".jj", target)
  end
  return vim.uv.fs_realpath(target)
end

local function debounced(on_change)
  local timer = assert(vim.uv.new_timer())
  return function()
    timer:stop()
    timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(on_change))
  end
end

local function watch(path, flags, on_event)
  if watchers[path] then
    return
  end
  local event = assert(vim.uv.new_fs_event())
  event:start(path, flags, on_event)
  watchers[path] = event
end

-- Every snapshot writes below .jj, and colocated repos write below .git,
-- so events there would loop.
local function is_metadata(name)
  local padded = "/" .. (name or "") .. "/"
  return padded:find("/.jj/", 1, true) or padded:find("/.git/", 1, true)
end

-- Watches the operation heads of root's repo and the files of root. A
-- file edit reaches jj only through a snapshot, which on_change takes by
-- running jj. libuv watches recursively on macOS and Windows only.
function M.start(root, on_change)
  local repo = repo_dir(root)
  if not repo then
    return
  end

  watch(vim.fs.joinpath(repo, "op_heads", "heads"), {}, debounced(on_change))
  local on_file = debounced(on_change)
  watch(root, { recursive = true }, function(_, name)
    if not is_metadata(name) then
      on_file()
    end
  end)
end

return M
