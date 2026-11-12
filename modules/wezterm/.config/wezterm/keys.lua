-- The key table, after the usual macOS terminal keys. WezTerm's own
-- defaults stay off, since several of them, such as Alt-Enter and
-- Ctrl-Shift-Space, take keys that the shell, Neovim, and agents use.
local wezterm = require("wezterm")
local act = wezterm.action
local copymode = require("copymode")

local M = {}

local IS_MAC = wezterm.target_triple:find("darwin") ~= nil

-- Clears the screen: drops the scrollback and lets the shell redraw.
local CLEAR_SCREEN = act.Multiple({
  act.ClearScrollback("ScrollbackAndViewport"),
  act.SendKey({ key = "l", mods = "CTRL" }),
})

-- Ctrl-Shift bindings, on every platform.
local SHARED = {
  { key = "c", mods = "CTRL|SHIFT", action = copymode.copy(act.CopyTo("Clipboard")) },
  { key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
  { key = "n", mods = "CTRL|SHIFT", action = act.SpawnWindow },
  { key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "phys:Equal", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
  { key = "phys:Minus", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
  { key = "phys:0", mods = "CTRL|SHIFT", action = act.ResetFontSize },
  { key = "f", mods = "CTRL|SHIFT", action = act.ToggleFullScreen },
  { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
  { key = "Tab", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
}

-- macOS Cmd bindings.
local MAC = {
  { key = "c", mods = "SUPER", action = copymode.copy(act.CopyTo("Clipboard")) },
  { key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },
  { key = "v", mods = "SUPER|SHIFT", action = act.PasteFrom("PrimarySelection") },
  { key = "=", mods = "SUPER", action = act.IncreaseFontSize },
  { key = "+", mods = "SUPER", action = act.IncreaseFontSize },
  { key = "-", mods = "SUPER", action = act.DecreaseFontSize },
  { key = "0", mods = "SUPER", action = act.ResetFontSize },
  { key = ",", mods = "SUPER|SHIFT", action = act.ReloadConfiguration },
  { key = "p", mods = "SUPER|SHIFT", action = act.ActivateCommandPalette },
  { key = "i", mods = "SUPER|ALT", action = act.ShowDebugOverlay },

  { key = "n", mods = "SUPER", action = act.SpawnWindow },
  { key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "SUPER", action = act.CloseCurrentPane({ confirm = false }) },
  { key = "w", mods = "SUPER|ALT", action = act.CloseCurrentTab({ confirm = false }) },
  { key = "q", mods = "SUPER", action = act.QuitApplication },
  { key = "h", mods = "SUPER", action = act.HideApplication },
  { key = "m", mods = "SUPER", action = act.Hide },
  { key = "Enter", mods = "SUPER", action = act.ToggleFullScreen },
  { key = "f", mods = "SUPER|CTRL", action = act.ToggleFullScreen },

  { key = "[", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },
  { key = "{", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "}", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },
  { key = "9", mods = "SUPER", action = act.ActivateTab(-1) },

  { key = "d", mods = "SUPER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "SUPER|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "Enter", mods = "SUPER|SHIFT", action = act.TogglePaneZoomState },
  { key = "[", mods = "SUPER", action = act.ActivatePaneDirection("Prev") },
  { key = "]", mods = "SUPER", action = act.ActivatePaneDirection("Next") },

  { key = "k", mods = "SUPER", action = CLEAR_SCREEN },
  { key = "f", mods = "SUPER", action = act.Search("CurrentSelectionOrEmptyString") },
  { key = "Home", mods = "SUPER", action = act.ScrollToTop },
  { key = "End", mods = "SUPER", action = act.ScrollToBottom },
  { key = "PageUp", mods = "SUPER", action = act.ScrollByPage(-1) },
  { key = "PageDown", mods = "SUPER", action = act.ScrollByPage(1) },
  { key = "UpArrow", mods = "SUPER", action = act.ScrollToPrompt(-1) },
  { key = "DownArrow", mods = "SUPER", action = act.ScrollToPrompt(1) },
  { key = "UpArrow", mods = "SUPER|SHIFT", action = act.ScrollToPrompt(-1) },
  { key = "DownArrow", mods = "SUPER|SHIFT", action = act.ScrollToPrompt(1) },

  -- Line editing: Cmd-Left and Cmd-Right send Ctrl-A and Ctrl-E, and
  -- Cmd-Backspace sends Ctrl-U. Option-Left and Option-Right move by word.
  { key = "LeftArrow", mods = "SUPER", action = act.SendString("\x01") },
  { key = "RightArrow", mods = "SUPER", action = act.SendString("\x05") },
  { key = "Backspace", mods = "SUPER", action = act.SendString("\x15") },
  { key = "LeftArrow", mods = "ALT", action = act.SendString("\x1bb") },
  { key = "RightArrow", mods = "ALT", action = act.SendString("\x1bf") },
}

-- Pane moves on Cmd-Alt-arrows and resizes on Cmd-Ctrl-arrows.
local DIRECTIONS = { UpArrow = "Up", DownArrow = "Down", LeftArrow = "Left", RightArrow = "Right" }
for key, direction in pairs(DIRECTIONS) do
  table.insert(MAC, { key = key, mods = "SUPER|ALT", action = act.ActivatePaneDirection(direction) })
  table.insert(MAC, { key = key, mods = "SUPER|CTRL", action = act.AdjustPaneSize({ direction, 5 }) })
end

for i = 1, 8 do
  table.insert(MAC, { key = tostring(i), mods = "SUPER", action = act.ActivateTab(i - 1) })
end

local COPY_DESTINATION = "ClipboardAndPrimarySelection"

-- Leaves copy mode like tmux's cancel: the selection clears and the view
-- returns to the bottom.
local LEAVE_COPY_MODE = act.Multiple({
  act.CopyMode("ClearSelectionMode"),
  act.ScrollToBottom,
  act.CopyMode("Close"),
})

-- Leaves the copy mode that a drag started. The view stays where the
-- drag left it.
local LEAVE_DRAG_COPY_MODE = act.Multiple({ act.CopyMode("ClearSelectionMode"), act.CopyMode("Close") })

-- Panes whose copy mode a drag started, by pane id.
local drag_copy_mode = {}

-- Copies the finished mouse selection and names its size in the status
-- line. A drag also leaves copy mode, like tmux's default
-- copy-pipe-and-cancel. A click in copy mode that a drag didn't start
-- drops the copy-mode selection, which the click cleared on screen, so
-- the next key starts afresh.
local COPY_SELECTION = wezterm.action_callback(function(window, pane)
  local id = pane:pane_id()
  local from_drag = drag_copy_mode[id]
  drag_copy_mode[id] = nil

  local action = act.CompleteSelection(COPY_DESTINATION)
  if window:active_key_table() == "copy_mode" then
    local after = act.CopyMode("ClearSelectionMode")
    if from_drag then
      after = LEAVE_DRAG_COPY_MODE
    elseif window:get_selection_text_for_pane(pane) ~= "" then
      after = LEAVE_COPY_MODE
    end
    action = act.Multiple({ action, after })
  end
  window:perform_action(copymode.copy(action), pane)
end)

-- Enters copy mode on the first drag event, as tmux does, then extends
-- the selection by unit. Outside copy mode WezTerm drops a selection
-- when output changes one of its rows. Entering copy mode clears the
-- selection, so the extension waits for that and starts anew at the
-- first drag position, next to the click.
local function drag_selection(unit)
  return wezterm.action_callback(function(window, pane)
    if window:active_key_table() ~= "copy_mode" then
      drag_copy_mode[pane:pane_id()] = true
      window:perform_action(act.ActivateCopyMode, pane)
    end
    window:perform_action(act.ExtendSelectionToMouseCursor(unit), pane)
  end)
end

-- The wheel scrolls as WezTerm does, and copymode.scrolled() follows up in
-- copy mode.
local WHEEL = act.Multiple({ act.ScrollByCurrentEventWheelDelta, copymode.scrolled() })

-- Cmd-click, or Ctrl-click off macOS, opens a link, and a plain click only
-- selects. The press does nothing, so Neovim doesn't see it. The link
-- bindings also apply while a program holds the mouse. A double click
-- copies the word and a triple click the line, except in programs that
-- hold the mouse, so Neovim gets those clicks to open files.
local function mouse_bindings()
  local link_mods = IS_MAC and "SUPER" or "CTRL"
  local bindings = {
    {
      event = { Up = { streak = 1, button = "Left" } },
      mods = "NONE",
      action = COPY_SELECTION,
    },
  }
  for streak, unit in pairs({ [1] = "Cell", [2] = "Word", [3] = "Line" }) do
    table.insert(bindings, {
      event = { Drag = { streak = streak, button = "Left" } },
      mods = "NONE",
      action = drag_selection(unit),
    })
  end
  for streak, unit in pairs({ [2] = "Word", [3] = "Line" }) do
    table.insert(bindings, {
      event = { Down = { streak = streak, button = "Left" } },
      mods = "NONE",
      action = act.SelectTextAtMouseCursor(unit),
    })
    table.insert(bindings, {
      event = { Up = { streak = streak, button = "Left" } },
      mods = "NONE",
      action = COPY_SELECTION,
    })
  end
  for _, button in ipairs({ { WheelUp = 1 }, { WheelDown = 1 } }) do
    table.insert(bindings, {
      event = { Down = { streak = 1, button = button } },
      mods = "NONE",
      alt_screen = false,
      action = WHEEL,
    })
  end
  for _, reporting in ipairs({ false, true }) do
    table.insert(bindings, {
      event = { Up = { streak = 1, button = "Left" } },
      mods = link_mods,
      mouse_reporting = reporting,
      action = act.OpenLinkAtMouseCursor,
    })
    table.insert(bindings, {
      event = { Down = { streak = 1, button = "Left" } },
      mods = link_mods,
      mouse_reporting = reporting,
      action = act.Nop,
    })
  end
  return bindings
end

-- Search keys: Cmd-G and Cmd-Shift-G step through matches, and
-- Cmd-Shift-F closes the search.
local function search_mode()
  local keys = wezterm.gui.default_key_tables().search_mode
  table.insert(keys, { key = "g", mods = "SUPER", action = act.CopyMode("NextMatch") })
  table.insert(keys, { key = "g", mods = "SUPER|SHIFT", action = act.CopyMode("PriorMatch") })
  table.insert(keys, { key = "f", mods = "SUPER|SHIFT", action = act.CopyMode("Close") })
  return keys
end

-- Copy mode keys that follow tmux's copy-mode.conf: v, V, and C-v
-- select, y copies and leaves, and Escape, q, C-c, and C-g leave. Y
-- copies to the end of the line and stays, like tmux's copy-end-of-line.
-- o and i jump between prompts, and / and ? search. WezTerm's search
-- starts upward, so Enter moves up and Ctrl-n down.
--
-- WezTerm applies a copy-mode selection only after the action that makes
-- it, so Y copies in copymode.copy(), a callback that runs later. Space is
-- written " ", since "Space" names the physical key and leaves WezTerm's
-- own binding of the mapped key in place.
local COPY_MODE = {
  { key = "v", mods = "NONE", action = copymode.select("Cell") },
  { key = " ", mods = "NONE", action = copymode.select("Cell") },
  { key = "V", mods = "NONE", action = copymode.select("Line") },
  { key = "V", mods = "SHIFT", action = copymode.select("Line") },
  { key = "v", mods = "CTRL", action = copymode.select("Block") },
  {
    key = "y",
    mods = "NONE",
    action = copymode.copy(act.Multiple({ act.CompleteSelection(COPY_DESTINATION), LEAVE_COPY_MODE })),
  },
  {
    key = "Y",
    mods = "SHIFT",
    action = act.Multiple({
      act.CopyMode("ClearSelectionMode"),
      act.CopyMode({ SetSelectionMode = "Cell" }),
      act.CopyMode("MoveToEndOfLineContent"),
      copymode.copy(act.Multiple({
        act.CompleteSelection(COPY_DESTINATION),
        act.CopyMode("MoveToSelectionOtherEnd"),
        act.CopyMode("ClearSelectionMode"),
      })),
    }),
  },
  { key = "Escape", mods = "NONE", action = LEAVE_COPY_MODE },
  { key = "q", mods = "NONE", action = LEAVE_COPY_MODE },
  { key = "c", mods = "CTRL", action = LEAVE_COPY_MODE },
  { key = "g", mods = "CTRL", action = LEAVE_COPY_MODE },
  { key = "o", mods = "NONE", action = act.CopyMode({ MoveBackwardZoneOfType = "Prompt" }) },
  { key = "i", mods = "NONE", action = act.CopyMode({ MoveForwardZoneOfType = "Prompt" }) },
  { key = "/", mods = "NONE", action = act.CopyMode("EditPattern") },
  { key = "?", mods = "SHIFT", action = act.CopyMode("EditPattern") },
}

-- WezTerm's copy_mode table with COPY_MODE after it. A later binding of
-- the same key wins.
local function copy_mode()
  local keys = wezterm.gui.default_key_tables().copy_mode
  for _, binding in ipairs(COPY_MODE) do
    table.insert(keys, binding)
  end
  return keys
end

function M.apply(config)
  config.disable_default_key_bindings = true
  config.keys = config.keys or {}
  for _, binding in ipairs(SHARED) do
    table.insert(config.keys, binding)
  end
  if IS_MAC then
    for _, binding in ipairs(MAC) do
      table.insert(config.keys, binding)
    end
  end

  config.mouse_bindings = mouse_bindings()

  -- wezterm.gui is absent when a headless mux server loads the config.
  if wezterm.gui then
    config.key_tables = config.key_tables or {}
    config.key_tables.search_mode = search_mode()
    config.key_tables.copy_mode = copy_mode()
  end
end

return M
