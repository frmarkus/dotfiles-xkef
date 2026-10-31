-- Keeps new panes in the agent VM that `agents vm` boots. A pane runs in
-- the VM when its shell reports an agentvm host through OSC 7. Splits
-- and new tabs of that pane run `agents vm pane` in the same directory,
-- which exists in the guest because `agents vm` copies repositories to
-- their host paths.
-- Every pane stays in the local mux. vm.lua loads this file.
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- The prefix of the host names that `agents vm` reports. Each VM takes
-- its container's name, such as agentvm-4242-17.
M.HOST = "agentvm"
-- The shield that marks sandbox panes in tab titles and the status line.
M.MARK = ""

-- The directory for pasted images, which the VM mounts at the same path.
local CLIPBOARD_DIR = wezterm.home_dir .. "/.cache/agentvm-clipboard"

-- Writes the clipboard's PNG to the path in argv, and fails when the
-- clipboard holds no image.
local SAVE_PNG = [[
on run argv
  set png to the clipboard as «class PNGf»
  set f to open for access POSIX file (item 1 of argv) with write permission
  write png to f
  close access f
end run]]

-- A tab with a shell in the VM, on a copy of the current repository.
M.shell_tab = act.SpawnCommandInNewTab({ args = { "agents", "vm", "shell" } })

-- The directory in cwd, a URL from OSC 7, when it names the VM, else nil.
local function vm_path(cwd)
  if cwd and cwd.host and cwd.host:sub(1, #M.HOST) == M.HOST then
    return cwd.file_path
  end
end

-- The pane's directory when the pane runs in the VM, else nil. During a
-- switch, WezTerm can pass a pane the mux already dropped, and the lookup
-- then throws.
local function vm_dir(pane)
  local ok, cwd = pcall(pane.get_current_working_dir, pane)
  return ok and vm_path(cwd) or nil
end

-- Whether the pane runs in the VM.
function M.in_vm(pane)
  return vm_dir(pane) ~= nil
end

-- Whether the pane in a PaneInformation, as tab titles get it, runs in the VM.
function M.info_in_vm(info)
  local ok, cwd = pcall(function()
    return info.current_working_dir
  end)
  return ok and vm_path(cwd) ~= nil
end

-- Splits toward direction, "Right" or "Down", in the VM for a VM pane
-- and with action for any other pane. The VM reports the directory, so
-- it goes to `agents vm pane`, which checks it, and never becomes the
-- host's working directory.
function M.split(action, direction)
  return wezterm.action_callback(function(window, pane)
    local dir = vm_dir(pane)
    local split = dir
        and act.SplitPane({ direction = direction, command = { args = { "agents", "vm", "pane", dir } } })
      or action
    window:perform_action(split, pane)
  end)
end

-- Opens a tab in the VM for a VM pane and with action for any other pane.
function M.tab(action)
  return wezterm.action_callback(function(window, pane)
    local dir = vm_dir(pane)
    local spawn = dir and act.SpawnCommandInNewTab({ args = { "agents", "vm", "pane", dir } }) or action
    window:perform_action(spawn, pane)
  end)
end

-- Pastes with action. In a VM pane, an image on the clipboard pastes as
-- the path of a PNG copy instead, since the guest has no clipboard and
-- Claude Code there attaches an image only from its path. Copies older
-- than a day go.
function M.paste(action)
  return wezterm.action_callback(function(window, pane)
    if M.in_vm(pane) then
      local path = string.format("%s/%s.png", CLIPBOARD_DIR, os.date("%Y%m%d-%H%M%S"))
      local ok = wezterm.run_child_process({
        "sh",
        "-c",
        'mkdir -p "$1" && find "$1" -name "*.png" -mtime +0 -delete && osascript -e "$2" "$3"',
        "sh",
        CLIPBOARD_DIR,
        SAVE_PNG,
        path,
      })
      if ok then
        pane:send_paste(path)
        return
      end
    end
    window:perform_action(action, pane)
  end)
end

return M
