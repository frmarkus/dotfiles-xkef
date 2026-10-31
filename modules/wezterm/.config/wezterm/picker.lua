-- Opens a tv picker script in a zoomed split and acts on its choice.
--
-- A script reports its choice by setting a user var on its own pane, such
-- as switch_workspace, and lingers until this module closes the pane. The
-- panes live in the mux server, and WezTerm never fires user-var-changed
-- for those: wezterm-client/src/pane/clientpane.rs stores the var without
-- notifying the GUI. So this polls the picker pane's vars while it's open.
--
-- The GUI numbers its panes apart from the mux server, so a script never
-- gets a pane id from here. It asks `wezterm cli`, which uses the server's
-- ids, and finds the pane it opened over with `get-pane-direction up`.
local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

local POLL_SECONDS = 0.05

local handlers = {}

-- Registers handler(window, value) for the user var name.
function M.on(name, handler)
  handlers[name] = handler
end

local function watch(window, pane_id)
  local ok, pane = pcall(wezterm.mux.get_pane, pane_id)
  if not ok or not pane then
    return
  end

  local vars = pane:get_user_vars()
  for name, handler in pairs(handlers) do
    local value = vars[name]
    if value and value ~= "" then
      window:perform_action(act.CloseCurrentPane({ confirm = false }), pane)
      handler(window, value)
      return
    end
  end

  wezterm.time.call_after(POLL_SECONDS, function()
    watch(window, pane_id)
  end)
end

-- Opens args in a zoomed split in the pane's directory and returns the
-- split. WezTerm has no floating panes, and a zoomed split stands in for
-- one: it covers the tab, `z` reveals the panes beneath, and the split
-- closes when the program exits. No args opens a shell.
--
-- A pane's directory comes from whatever runs in it, through OSC 7. Only
-- a report from this machine counts: a VM pane could name a host folder
-- it wrote, and git there would run the guest's hooks on the host.
function M.split(window, pane, args)
  local cwd = pane:get_current_working_dir()
  local here = cwd and (cwd.host == "" or cwd.host == "localhost" or cwd.host == wezterm.hostname())
  local split = pane:split({ args = args, cwd = here and cwd.file_path or nil, direction = "Bottom" })
  window:perform_action(act.SetPaneZoomState(true), split)
  return split
end

function M.open(args)
  return wezterm.action_callback(function(window, pane)
    watch(window, M.split(window, pane, args):pane_id())
  end)
end

return M
