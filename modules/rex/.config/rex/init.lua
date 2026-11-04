-- Rex on the tmux prefix keys of ~/.config/tmux/conf.d/keys.conf. Rex has
-- no copy mode, status line, pane picker, or last-window action, and the
-- theme and font live in the app's settings.
-- See https://www.superlogical.com/rex/docs/customize/config
--
-- Rex matches keys unshifted, so a shifted symbol is written as the U.S.
-- layout key that types it: | is shift+\ and * is shift+8.

local PREFIX = "ctrl+space>"
local TERMINAL = "com.superlogical.terminal"
local RESIZE_STEP = 5

local DIRECTIONS = { h = "left", j = "down", k = "up", l = "right" }

local CENTER_80 = { 0.1, 0.1, 0.8, 0.8 }
local CENTER_90 = { 0.05, 0.05, 0.9, 0.9 }

-- Programs that open in a floating layer in the focused pane's directory.
-- Rex has no modal pane, so the tmux modal tools float too.
local TOOLS = {
  { key = "shift+8", name = "float_shell", title = "Floating Shell", bounds = CENTER_80 },
  { key = "e", name = "yazi", title = "File Manager (yazi)", command = { "yazi" }, bounds = CENTER_80 },
  { key = "shift+g", name = "jjui", title = "jj UI (jjui)", command = { "jjui" }, bounds = CENTER_80 },
  { key = "g", name = "lazygit", title = "Lazygit", command = { "lazygit" }, bounds = CENTER_90 },
  { key = "shift+r", name = "scooter", title = "Search and Replace", command = { "scooter" }, bounds = CENTER_90 },
  { key = "d", name = "lazydocker", title = "Lazydocker", command = { "lazydocker" }, bounds = CENTER_90 },
  { key = "shift+t", name = "htop", title = "Process Viewer", command = { "htop" }, bounds = { 0.1, 0.02, 0.8, 0.6 } },
  { key = "shift+/", name = "keys", title = "Key Reference", command = { "dots-ref" }, bounds = { 0.15, 0.075, 0.7, 0.85 } },
}

local function prefix(key, action, args)
  rex.bind(PREFIX .. key, action, args)
end

local function foreground()
  local process = rex.block.call(TERMINAL, "process", {})
  return process and process.foreground
end

-- smart-splits.nvim moves and resizes Neovim splits on Ctrl-hjkl and
-- Alt-Shift-hjkl, so the keys go to Neovim instead of Rex.
local function in_nvim()
  local fg = foreground()
  return fg ~= nil and fg.name == "nvim"
end

local function resize(args)
  if in_nvim() then
    rex.client.queue("pane.send_key", { key = "alt+shift+" .. args.key })
    return
  end

  rex.client.queue("pane.resize", { direction = args.direction, amount = RESIZE_STEP })
end

local MOVE_ARGS = { key = "string", direction = "string" }

rex.action({
  name = "navigate",
  title = "Focus Pane or Neovim Split",
  args = MOVE_ARGS,
  run = function(_, args)
    if in_nvim() then
      rex.client.queue("pane.send_key", { key = "ctrl+" .. args.key })
      return
    end

    rex.client.queue("pane.focus", { direction = args.direction })
  end,
})

rex.action({
  name = "resize",
  title = "Resize Pane or Neovim Split",
  args = MOVE_ARGS,
  run = function(_, args)
    resize(args)
  end,
})

-- Rex has no repeat timer for tmux's `bind -r`. The resize mode keeps
-- hjkl resizing until Escape or Enter.
rex.action({
  name = "resize_repeat",
  title = "Resize Pane and Keep Resizing",
  args = MOVE_ARGS,
  run = function(_, args)
    resize(args)
    rex.client.queue("client.mode.enter", { name = "resize" })
  end,
})

rex.mode("resize", { exclusive = true })
rex.bind("resize/enter", "client.mode.exit")

for key, direction in pairs(DIRECTIONS) do
  local args = { key = key, direction = direction }
  prefix(key, "navigate", args)
  prefix("shift+" .. key, "resize_repeat", args)
  rex.bind("resize/" .. key, "resize", args)
  rex.bind("resize/shift+" .. key, "resize", args)
end

for _, tool in ipairs(TOOLS) do
  rex.action({
    name = tool.name,
    title = tool.title,
    run = function()
      local fg = foreground()
      return assert(rex.session.new_layer({
        bounds = tool.bounds,
        focus = true,
        layout = rex.layout.block({
          flavor = TERMINAL .. ".shell",
          options = { command = tool.command, cwd = fg and fg.cwd },
        }),
      }))
    end,
  })
  prefix(tool.key, tool.name)
end

prefix("r", "client.config.reload")
prefix("ctrl+l", TERMINAL .. ".clear")

-- Panes
prefix("shift+\\", "pane.split", { direction = "right" })
prefix("-", "pane.split", { direction = "down" })
prefix("z", "pane.zoom")
prefix("x", "pane.close")
prefix("shift+2", "pane.float")
prefix("shift+1", "pane.move_to_new_tab")
prefix("shift+w", "pane.move_to_tab")

-- Windows, which Rex calls tabs
prefix("c", "client.tab.new")
prefix("n", "client.tab.next")
prefix("p", "client.tab.previous")
prefix("shift+,", "client.tab.move.backward")
prefix("shift+.", "client.tab.move.forward")
prefix(",", "client.tab.rename")
prefix("shift+7", "client.tab.close")
prefix("w", "client.sidebar.filter.focus")
for index = 1, 9 do
  prefix(tostring(index), "client.tab.goto", { index = index })
end

-- Sessions
prefix("f", "session.switch")
prefix("s", "session.switch")
prefix("shift+s", "session.new")
prefix("shift+4", "session.rename")
prefix("shift+9", "session.previous")
prefix("shift+0", "session.next")

-- Scrollback
prefix("o", "client.prompt.previous")
prefix("i", "client.prompt.next")
