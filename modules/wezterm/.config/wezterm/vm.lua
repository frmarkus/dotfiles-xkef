-- Panes in the agent VM, through agentvm.lua, on a Mac with the agentvm
-- package, whose engine sits in ~/.local/libexec. Elsewhere every pane is
-- local, and each wrapper returns its action unchanged.
local wezterm = require("wezterm")

local engine = io.open(wezterm.home_dir .. "/.local/libexec/agentvm/agentvm")
if engine then
  engine:close()
end
if wezterm.target_triple:find("darwin") and engine then
  return require("agentvm")
end

local M = {}

local function passthrough(action)
  return action
end

function M.in_vm()
  return false
end

M.info_in_vm = M.in_vm
M.split = passthrough
M.tab = passthrough
M.paste = passthrough

return M
