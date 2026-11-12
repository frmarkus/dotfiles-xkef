-- Leader bindings and palette entries for the agents package. leader.lua
-- adds them when the package is deployed.
local picker = require("picker")

local M = {}

local PICKER = picker.open({ "agents" })

M.keys = {
  -- @key wezterm :: a :: Agent picker (all workspaces)
  { key = "a", mods = "LEADER", action = PICKER },
}

M.palette = {
  { brief = "Agents", icon = "cod_hubot", action = PICKER },
}

return M
