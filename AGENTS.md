# Repository instructions

## Version control

This repository uses Jujutsu, `jj`, in colocated mode. The `.jj/` directory
belongs to the repo state.

- Use `jj` for status, diff, history, commit, bookmark, rebase, squash, and
  split operations.
- Don't use `git status`, `git diff`, `git add`, `git commit`, `git checkout`,
  `git reset`, or `git stash` unless the user asks for a Git command or the
  operation inspects Git objects.
- When committing, use the `commit` skill and the `jj` skill if available.
- Pass file paths to mutating jj commands so unrelated user changes stay out of
  the operation.
- Never include `.claude-notes/` or ignored local runtime and config files in a
  commit unless the user asks.

## GitHub accounts

More than one gh login exists. The primary account holds this repo and sits
keyring-active in gh. git and jj pushes route through `gh auth git-credential`,
which picks the active account. To run one command as another account without
touching global state, set `GH_TOKEN` inline. The credential helper follows it,
so this routes `gh`, `git`, and `jj git push` alike:

    GH_TOKEN=$(gh auth token --user <account>) <cmd...>

A repo that another account holds can pin it for the whole directory through
mise, as in this `mise.local.toml`:

    [env]
    GH_TOKEN = "{{ exec(command='gh auth token --user <account>') }}"

Leave out `cache_key`. With it, mise writes the token to its cache directory.

Don't run `gh auth switch`. It misroutes concurrent sessions. A stray
`GITHUB_TOKEN` in the environment pins plain `gh` to that account. `GH_TOKEN`
overrides it, or prefix the command with `env -u GITHUB_TOKEN`.

## Verification

Run `mise run ci` before every commit, and fix what it reports. CI runs the same
task, so a skipped run breaks main. `mise tasks --hidden` lists the single
checks, such as `mise run test:private`, for a faster loop.
