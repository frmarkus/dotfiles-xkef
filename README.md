# dotfiles

[![CI](https://github.com/xkef/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.com/xkef/dotfiles/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/xkef/dotfiles/badge)](https://scorecard.dev/viewer/?uri=github.com/xkef/dotfiles)

![screenshot](.github/scrot.png)

macOS and Arch Linux dotfiles, applied by one fish script, `setup/apply`.

## Install

```bash
git clone https://github.com/xkef/dotfiles ~/dotfiles
~/dotfiles/setup/bootstrap
```

Bootstrap installs the `core` packages, which bring fish, then runs
`setup/apply`. After that, `dots apply` runs it again. Each run prints its
pipeline, which [`setup/apply`](setup/apply) lists, and then works through it.
Each step can run again without harm, so a rerun repairs whatever drifted.
`dots diff` prints the link changes without making them.

The machine's state lives in `~/.local/state/dotfiles`, which the repo links as
`state/`, next to the agent VM's state at `~/.local/state/agentvm`, linked as
`vm/`:

- `modules` selects the modules under `modules/`. A machine gets `core`,
  `desktop`, and `agents`, plus `agentvm` on macOS, and the agent VM gets `core`
  and `agents`. The extras `wezterm`, `rex`, `helix`, `zed`, and `kickstart` go
  in by hand.
- `links` lists every link the last run made, so a file removed from the repo
  loses its link.
- `backup/` holds the files that stood where a link goes.

## Included tools

| Tool                                                                               | What it does                                               |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| [Fish](https://fishshell.com)                                                      | Shell with tv pickers and practical defaults               |
| [Starship](https://starship.rs)                                                    | Minimal, cross-shell prompt                                |
| [Neovim](https://neovim.io) + [LazyVim](https://www.lazyvim.org)                   | Editor with the LazyVim distro                             |
| [Ghostty](https://ghostty.org)                                                     | Terminal that runs tmux, themed with the rest              |
| [tmux](https://github.com/tmux/tmux) + [sesh](https://github.com/joshmedeski/sesh) | Multiplexer and sessions, with an agent picker             |
| [WezTerm](https://wezterm.org)                                                     | Extra: terminal and multiplexer, on the tmux keys          |
| [Rex](https://www.superlogical.com/rex)                                            | Extra: multiplexer app in beta, on the tmux keys           |
| [television](https://github.com/alexpasmantier/television)                         | Fuzzy finder in the shell and the pickers                  |
| [atuin](https://atuin.sh)                                                          | Searchable local shell history                             |
| [Claude Code](https://claude.com/claude-code), [pi](https://pi.dev)                | AI coding agents, always launched in a nono sandbox        |
| [Jujutsu](https://github.com/jj-vcs/jj)                                            | Git-compatible version control, `jj`, with a simpler model |
| [container](https://github.com/apple/container)                                    | Sandbox VM for agents, with no network device             |
| [Vale](https://vale.sh)                                                            | Prose linter for markdown, Google style plus AI-tell rules |
| eza, bat, fd, ripgrep, zoxide, yazi, mise                                          | Command-line replacements and workflow tools               |

## Keys

Neovim uses `Space` as leader, and WezTerm and tmux use `Ctrl-Space`. `leader ?`
lists the bindings. `dots theme` switches the colors of every themed tool at
once.

## Agent sandbox

`claude` and `pi` start in a [nono](https://nono.sh) sandbox, whose credential
proxy adds the Claude and GitHub tokens to requests. `agents vm` runs Claude
Code in a VM with no network device, which reaches only the same proxy.
`agents vm update` builds its image. Store the tokens once:

```sh
claude setup-token  # then store its output:
security add-generic-password -s nono -a claude_code_oauth_token -w
security add-generic-password -s nono -a github-<gh user> -w
security add-generic-password -s nono -a openrouter_api_key -w  # pi
# Linux: secret-tool store --label=nono service nono account github-<gh user>
```

pi starts on DeepSeek V4.1 Flash through OpenRouter. Its footer shows the
session's cost, and the status line shows the key's spend today and this month.

## Private files

Private files, such as the git identity, live in `private/home.tar.age`, an
[age](https://age-encryption.org) archive whose key sits in 1Password. A desktop
apply unpacks it into `$HOME`, next to the configs that include each file.
`mise run encrypt <file>` adds or updates one and signs the archive with git's
signing key. The apply refuses an archive without a signature from a key in
`private/allowed_signers`.

## Credits

Inspired by [wincent/wincent](https://github.com/wincent/wincent), with
borrowings from [omerxx/dotfiles](https://github.com/omerxx/dotfiles),
[ThePrimeagen](https://github.com/ThePrimeagen/.dotfiles), and
[LazyVim](https://github.com/LazyVim/LazyVim).
