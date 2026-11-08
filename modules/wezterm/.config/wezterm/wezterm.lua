-- WezTerm is the terminal, the multiplexer, and the status line in one
-- process. Each module owns one concern:
--
--   path.lua        PATH for panes and helper programs
--   colors.lua      the palette of the theme that `theme` applied
--   keys.lua        macOS-style key and mouse bindings, and copy mode keys
--   copymode.lua    copy-mode selections and copies
--   leader.lua      the leader, its bindings, and the command palette
--   picker.lua      tv pickers in a zoomed split, and their choices
--   workspaces.lua  workspace switching
--   status.lua      tab titles and the status line
--   vm.lua          new panes and tabs that stay in the agent VM
--
-- Two more load only when the agents package is deployed:
--
--   agentvm.lua     the agent VM behind vm.lua, on macOS
--   agents.lua      agent bindings
local wezterm = require("wezterm")
local config = wezterm.config_builder()

local IS_MAC = wezterm.target_triple:find("darwin") ~= nil

local FONT = "JetBrainsMono Nerd Font"

-- Faint text draws at half opacity.
local FAINT_OPACITY = 0.5

-- Space above and below the status line, in cells. The bottom window
-- padding sits between the panes and the bar, and the frame's bottom
-- border below it.
local STATUS_ABOVE = 0.5
local STATUS_BELOW = 0.25
local STATUS_UPDATE_MS = 500

local colors = require("colors")
colors.apply(config)
require("keys").apply(config)
require("leader").apply(config)
require("workspaces").setup()
require("status").setup()

-- Panes live in a local mux server, so closing the window detaches instead
-- of killing the shells. The next launch reattaches.
config.unix_domains = { { name = "unix" } }
config.default_gui_startup_args = { "connect", "unix" }
config.set_environment_variables = { PATH = require("path").PATH }

-- Panes reach the SSH agent through WezTerm's proxy, which forwards to the
-- GUI's SSH_AUTH_SOCK. From the Dock that is launchd's agent, so programs
-- that skip fish, such as the jjui overlay, can't sign commits. Forward to
-- 1Password, as fish/conf.d/1password.fish does. setup/apply links the
-- macOS socket to the Linux path.
local OP_AGENT_SOCK = wezterm.home_dir .. "/.1password/agent.sock"
if #wezterm.glob(OP_AGENT_SOCK) > 0 then
  config.default_ssh_auth_sock = OP_AGENT_SOCK
end

-- GitHub references such as wezterm/wezterm#1234 become links, and quick
-- select also hints jj change ids, which use only the letters k to z.
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  regex = [[\b([\w.-]+/[\w.-]+)#(\d+)\b]],
  format = "https://github.com/$1/issues/$2",
})
config.quick_select_patterns = { [[\b[k-z]{8,}\b]] }

config.font = wezterm.font(FONT)

-- WezTerm's own rules take ExtraBold for bold and Thin for faint text,
-- which look too heavy and too thin. Bold uses Bold, and faint text uses
-- the Regular face at half opacity: faint text in the default color blends
-- halfway to the background, and colored faint text keeps its color.
local faint = colors.blend(config.colors.foreground, config.colors.background, FAINT_OPACITY)
config.font_rules = {
  { intensity = "Bold", italic = false, font = wezterm.font(FONT, { weight = "Bold" }) },
  { intensity = "Bold", italic = true, font = wezterm.font(FONT, { weight = "Bold", style = "Italic" }) },
  { intensity = "Half", italic = false, font = wezterm.font(FONT, { foreground = faint }) },
  { intensity = "Half", italic = true, font = wezterm.font(FONT, { style = "Italic", foreground = faint }) },
}
config.font_size = 14
config.line_height = 1.2
config.bold_brightens_ansi_colors = "No"
config.adjust_window_size_when_changing_font_size = false

-- macOS hides the title bar but keeps the rounded, resizable frame. Linux
-- keeps its decorations.
if IS_MAC then
  config.window_decorations = "RESIZE"
end
config.window_padding = { left = 12, right = 12, top = 0, bottom = STATUS_ABOVE .. "cell" }
config.window_close_confirmation = "NeverPrompt"
config.native_macos_fullscreen_mode = true

-- The status line is a plain bar at the bottom on the terminal background,
-- styled by status.lua.
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
-- WezTerm redraws the bar when copy mode starts or a key table changes,
-- and the copymode.lua actions redraw it after each selection change. The
-- interval covers the rest, such as the clock, leaving copy mode, and a
-- mouse selection outside copy mode, and each tick reads the selection
-- text, so it stays coarse.
config.status_update_interval = STATUS_UPDATE_MS
config.tab_max_width = 34
config.colors.tab_bar = { background = config.colors.background }
config.window_frame = {
  border_bottom_height = STATUS_BELOW .. "cell",
  border_bottom_color = config.colors.background,
}

-- A grey 1px rule halfway through the padding above the bar, like the
-- tmux pane border that sat above its status line. It is a background
-- layer on top of the plain background color, offset up from the bottom
-- edge by the border, the bar, and half the padding.
local divider_offset = STATUS_BELOW + 1 + STATUS_ABOVE / 2
config.background = {
  { source = { Color = config.colors.background }, width = "100%", height = "100%" },
  {
    source = { Color = config.colors.brights[1] },
    width = "100%",
    height = "1px",
    repeat_y = "NoRepeat",
    vertical_align = "Bottom",
    vertical_offset = -divider_offset .. "cell",
  },
}

-- The window grows and shrinks by whole cells, so no leftover rows of
-- pixels land above the bar and skew the gaps.
config.use_resize_increments = true

-- Unfocused splits dim by a tenth.
config.inactive_pane_hsb = { saturation = 1.0, brightness = 0.9 }

config.default_cursor_style = "SteadyBar"
config.scrollback_lines = 50000

-- No system bell. Desktop notifications over OSC 9 show only
-- for a pane out of view.
config.audible_bell = "Disabled"
config.notification_handling = "SuppressFromFocusedTab"

-- Left Option sends Alt for the shell and tv bindings. Right Option still
-- types special characters such as @, [], and {}.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true

-- Per-machine overrides, untracked. local.lua returns a function that
-- changes config.
if package.searchpath("local", package.path) then
  require("local")(config)
end

return config
