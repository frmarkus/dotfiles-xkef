-- Colors from the theme that `theme` last applied. `theme` writes its
-- name, such as catppuccin-mocha, to $XDG_STATE_HOME/theme/current, and
-- the palette file of that name holds the colors in Ghostty's format, so
-- both terminals match. Watching the state file reloads the config, and
-- with it the colors, on every switch. Before `theme` first runs, WezTerm
-- keeps its own colors. `theme` alone holds the default theme.
local wezterm = require("wezterm")

local M = {}

local CONFIG_HOME = os.getenv("XDG_CONFIG_HOME") or (wezterm.home_dir .. "/.config")
local STATE_HOME = os.getenv("XDG_STATE_HOME") or (wezterm.home_dir .. "/.local/state")

-- Maps a palette file to WezTerm colors, or nil when the file is missing.
local function load_palette(path)
  local file = io.open(path)
  if not file then
    return nil
  end

  local colors = { ansi = {}, brights = {} }
  for line in file:lines() do
    local slot, hex = line:match("^palette = (%d+)=(#%x+)$")
    if slot then
      slot = tonumber(slot)
      if slot < 8 then
        colors.ansi[slot + 1] = hex
      else
        colors.brights[slot - 7] = hex
      end
    end
    local key, value = line:match("^([%w-]+) = (#%x+)$")
    if key == "background" then
      colors.background = value
    elseif key == "foreground" then
      colors.foreground = value
    elseif key == "cursor-color" then
      colors.cursor_bg, colors.cursor_border = value, value
    elseif key == "cursor-text" then
      colors.cursor_fg = value
    elseif key == "selection-background" then
      colors.selection_bg = value
    elseif key == "selection-foreground" then
      colors.selection_fg = value
    end
  end
  file:close()
  return colors
end

local function theme_colors()
  local current = STATE_HOME .. "/theme/current"
  wezterm.add_to_config_reload_watch_list(current)

  local file = io.open(current)
  if not file then
    return nil
  end
  local name = file:read("l")
  file:close()
  if not name or name == "" then
    return nil
  end
  return load_palette(CONFIG_HOME .. "/theme/palettes/" .. name)
end

-- Mixes two "#rrggbb" colors, with weight from 0 (all a) to 1 (all b).
function M.blend(a, b, weight)
  local mixed = {}
  for i = 2, 6, 2 do
    local x, y = tonumber(a:sub(i, i + 1), 16), tonumber(b:sub(i, i + 1), 16)
    table.insert(mixed, string.format("%02x", math.floor(x + (y - x) * weight + 0.5)))
  end
  return "#" .. table.concat(mixed)
end

-- Sets the colors on config and reloads it when `theme` switches.
function M.apply(config)
  config.colors = theme_colors() or wezterm.color.get_default_colors()
end

return M
