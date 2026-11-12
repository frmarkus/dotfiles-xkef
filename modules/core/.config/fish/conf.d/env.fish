# ── XDG Base Directories ─────────────────────────────
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx XDG_DATA_HOME $HOME/.local/share
set -gx XDG_STATE_HOME $HOME/.local/state
set -gx XDG_CACHE_HOME $HOME/.cache

# ── Telemetry opt-outs ───────────────────────────────
# DO_NOT_TRACK stays unset. Claude Code disables Remote Control, its
# feature-flag evaluation, when the variable exists.
# https://cli.github.com/telemetry
set -gx GH_TELEMETRY false
# https://docs.brew.sh/Analytics
set -gx HOMEBREW_NO_ANALYTICS 1
# https://github.com/cloudflare/workers-sdk/blob/main/packages/wrangler/telemetry.md
set -gx WRANGLER_SEND_METRICS false

# ── Package release cooldown ─────────────────────────
# Skip package versions published in the last 7 days. Malicious releases
# are usually reported and pulled within that window. npm counts days and
# pnpm counts minutes. mise and uv set theirs in their config files. The
# linked ~/.npmrc sets npm's for programs not started from fish.
set -gx npm_config_min_release_age 7
set -gx pnpm_config_minimum_release_age 10080

# ── Homebrew ─────────────────────────────────────────
if test -d /opt/homebrew
    set -gx HOMEBREW_PREFIX /opt/homebrew
    set -gx HOMEBREW_CELLAR /opt/homebrew/Cellar
    set -gx HOMEBREW_REPOSITORY /opt/homebrew
    set -q MANPATH; or set MANPATH ''
    set -gx MANPATH /opt/homebrew/share/man $MANPATH
    set -gx INFOPATH /opt/homebrew/share/info $INFOPATH
end

# ── Editor ───────────────────────────────────────────
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx NVIM_APPNAME lazyvim

if command -q nvim
    set -gx MANPAGER 'nvim +Man!'
    set -gx MANWIDTH 999
end

# ── XDG tool homes ──────────────────────────────────
set -gx CARGO_HOME $XDG_DATA_HOME/cargo
set -gx RUSTUP_HOME $XDG_DATA_HOME/rustup
set -gx GOPATH $XDG_DATA_HOME/go
set -gx GOBIN $GOPATH/bin
set -gx LESSHISTFILE $XDG_STATE_HOME/less/history
set -gx NODE_REPL_HISTORY $XDG_DATA_HOME/node_repl_history
# eza looks for theme.yml in ~/Library/Application Support on macOS.
set -gx EZA_CONFIG_DIR $XDG_CONFIG_HOME/eza
set -gx _ZO_EXCLUDE_DIRS "$HOME/Library/*:$HOME/.Trash/*:/tmp/*"

# ── Pager ────────────────────────────────────────────
set -gx PAGER less
# less underlines OSC 8 links, such as delta's line numbers. -DO- draws
# them as plain text, and they stay clickable.
set -gx LESS '-iFMRX --mouse -#.25 --use-color -DO-'
# Nerd Font icons sit in the Private Use Areas, which less otherwise
# shows as <U+E5FF>.
set -gx LESSUTFCHARDEF 'e000-f8ff:p,f0000-ffffd:p'

# ── PATH ─────────────────────────────────────────────
# One call in priority order. -m moves entries already in an inherited
# PATH, so a shell started from tmux or WezTerm gets the same order.
# Homebrew keeps rustup keg-only, so cargo and rustc need its opt path.
# It keeps curl keg-only too. macOS's own curl links LibreSSL 3.3, which
# has no ML-KEM, so its TLS key exchange is classical.
set -l paths $HOME/.local/bin $CARGO_HOME/bin $GOPATH/bin
if set -q HOMEBREW_PREFIX
    set -a paths $HOMEBREW_PREFIX/opt/rustup/bin $HOMEBREW_PREFIX/opt/curl/bin $HOMEBREW_PREFIX/bin $HOMEBREW_PREFIX/sbin
end
fish_add_path -gPm $paths /usr/local/bin
