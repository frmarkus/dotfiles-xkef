# ── Dotfiles directory ───────────────────────────────
# Resolved through this file's symlink into the repo, so dots, the pi
# launcher, and the LazyVim <leader>fC picker all agree on the repo path.
set -gx DOTFILES_DIR (string replace /modules/core/.config/fish/conf.d/dotfiles.fish '' (path resolve (status filename)))
