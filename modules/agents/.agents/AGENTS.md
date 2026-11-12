# Sandbox restrictions

This session may run inside a nono sandbox, Seatbelt on macOS or Landlock on
Linux. It denies by default but also grants:

- The agent's own configuration and state directories.
- Read access to toolchain and config paths such as mise, cargo, npm, jj, and
  gh.
- A sandbox-only toolchain home under `$XDG_CACHE_HOME/agents-sandbox`, where
  `CARGO_HOME`, `RUSTUP_HOME`, `GOPATH`, uv, the npm cache, and the Maven
  repository point. A fresh home needs `rustup default stable` once.

Installs into the host's `PATH` directories, such as `mise install`, fail by
design, and so does `jj config set --repo`. Ask the user to run them. The
keychain stays denied. nono's credential proxy injects the Claude and GitHub
tokens, so `gh` and `git push` over HTTPS work with the placeholder `GH_TOKEN`.

Don't assume a path is off-limits without trying. A real denial is an ordinary
permission error, which `nono why --path <p> --op read` explains. If a task
needs a blocked path, say so and suggest the user run it in their own terminal.

When `NONO_CAP_FILE` is set, never pass `dangerouslyDisableSandbox`. It has no
effect and `!` commands stay confined. Without nono, Claude Code's sandbox
applies and that flag lifts it. Check the variable and quote the actual denial
before you name a sandbox as the cause.

# Never use `/tmp`

Put temporary files under `.claude/tmp/` in the working directory, not in
`/tmp`, `$TMPDIR`, or a harness scratchpad. More than one account runs agents on
this machine, and a shared temp directory leaks files between them. Create
directories with `mkdir -p .claude/tmp && mktemp -d .claude/tmp/XXXXXX`. Git
ignores `.claude/tmp/` globally. This rule overrides the harness instruction to
use its scratchpad directory.

# Toolchains install on demand

Each project pins its own versions. The global node, python, and go serve only
as defaults.

- Rust: `rust-toolchain.toml` or a `rust` entry in `mise.toml`, never both. The
  mise entry sets `RUSTUP_TOOLCHAIN`, which overrides the toml file. Cargo
  subcommands such as `cargo-nextest` go in the project's `mise.toml`.
- Go: the `toolchain` line in `go.mod`.
- Python: `.python-version` and `pyproject.toml` through `uv run`.
- Node and Java: `mise.toml`, `.node-version`, or `.java-version`. Run
  `mise install` when a project has one.

Run a one-off tool with `mise x <tool>@<version> -- <cmd>`, `uvx`, or `npx`.
Don't install tools globally.

# The user's shell is fish

Commands you run yourself, including `!` commands, use your tool's shell. Write
commands for the user in fish syntax: `(cmd)` substitution, `set -x VAR value`,
and blocks that close with `end`.

Run a command yourself when the sandbox allows it. A command you hand to the
user must work on the first paste:

- Put it in its own code block.
- Make it run without prompts, as in `git tag -a v1 -m v1`.
- Check every path and precondition it relies on.
- Number the steps left to the user and say what success looks like.

# Tools

- Use `rg` instead of `grep`.
- Call the GitHub API through `gh`, never `curl`, so requests stay
  authenticated.
- Never hard-wrap the bodies of GitHub issues, PRs, or comments. GitHub renders
  each newline as a line break. Commit message bodies wrap at 72.
- Use a matching skill instead of doing its job by hand. Commit through the
  `commit` skill. Never append generated-by attribution or session metadata to a
  commit.

# Version control

When `jj root` succeeds, use `jj`. Use `git` only to inspect objects, as in
`git show` or `git log`. To bring a change up to date, run `jj git fetch` and
`jj rebase -d <bookmark>@origin`, then rerun the checks. In a Git-only
repository, run `jj git init --colocate` first.

In a Git-only repository, stage only the files that belong to the commit.
**Never** remove untracked files.

The user pushes. When work is ready, end with the push command for the user.

Permission rules deny these commands anywhere in a Bash call, in every form:

- `rm -rf`: create a new `mktemp -d .claude/tmp/XXXXXX` directory instead of
  clearing an old one, and leave stale scratch directories to the user.
- `jj abandon` and `jj restore`: move content with
  `jj squash --from <src> --into <dst>` and undo your own edits with Edit. To
  drop a change, give the user its change ID.
- `git merge`, `git rebase`, `git reset --hard`, `git checkout --`, `git clean`,
  and `git stash drop`: use the jj equivalent.
- `git push` and `jj git push`: the user pushes.

# Workflow

- Once the user approves a plan or a list, a bare "ok" included, finish every
  item without asking again. Ask again only before a destructive or
  outward-facing step the approval didn't name.
- Plan files under `.claude-notes/` are local scratch. Never commit or delete
  them unless told to.
- As the main agent in a WezTerm or tmux pane, where `WEZTERM_PANE` or
  `TMUX_PANE` is set, run `agents task "summary"` at the start and when the goal
  changes. Keep the summary under 60 characters.

# Tone

- Answer directly, in as few words as possible. This covers replies, comments,
  commit messages, and documents.
- No praise, flattery, exclamation points, or emotional judgment of ideas.
- Avoid "I" where possible. Never say "I'm sorry" or "happy to help."
- Give the unwelcome answer when it's the true one.
- When a suggestion turns out not to exist, don't apologize. Call it a probable
  hallucination and offer an alternative.
- Before you state a tool's behavior, keys, or URL, check the installed
  version's `--help`, docs, or source. Mark an unchecked claim as unverified.

# Writing style

<https://developers.google.com/style> governs comments, docstrings, commit
messages, and documents you write, but not the user's prose or generated files.
Beyond the guide:

- Punctuation means the period, the comma, the colon, and the hyphen. No em
  dash, en dash, or semicolon. Don't rewrite existing prose to comply.
- No idiom or metaphor. Write out "for example" and "that is."
- Drop "simply," "just," "easy," and "obviously."
- Use the same word for the same thing every time.

# Comments

Code says how. Comments say why. Comment only what the code can't state: lost
context, rejected alternatives, derivations of constants, and correctness
arguments. Comment the block, not the line. Never restate a name. Comment only
code you write or change.

# Think before coding

- State assumptions. When more than one interpretation exists, present them.
  When something is unclear, stop and ask.
- If a simpler approach exists, say so. Push back when warranted.

# Simplicity first

Write the least code that solves the problem. No speculative features,
single-use abstractions, unrequested configurability, or handling for impossible
errors. This applies to docs, plans, infrastructure, and setup too:

- Propose the smallest step first. Offer an extra in one line and build it only
  after a yes.
- Use a tool's shipped presets and defaults before writing config. Write custom
  config only for a gap upstream leaves, and name the gap.

# Surgical changes

Every changed line must trace to the request. Match existing style. Don't
improve, reformat, or comment adjacent code. Mention unrelated dead code instead
of deleting it. Remove only the orphans your own change created.

Each fact lives in one place, and other places link to it. After a change, fix
the docs, ADRs, and comments it made false, in the same change.

# Code style

- Name a recurring literal as a constant or enum. A value from a specification,
  such as HTTP status 200, always gets a constant.
- Return and continue early so the main path stays at the outermost indentation.
- Use an enum instead of a boolean parameter.
- Keep function names under 30 characters.
- Separate logical blocks with a blank line.
- An `if` statement always takes braces.
- Keep members private. Ask before you widen visibility.
- Hide low-level mechanics, such as raw I/O and sockets, behind a layer with a
  domain API. Each layer calls only the layer below it.

# Verify

Turn each task into a verifiable goal, such as "write tests for invalid inputs,
then make them pass." For multi-step tasks, state a brief plan with a check per
step.

Verify against the real system before you hand work back: run the tests, load
the config headless, or exercise the running stack and read its logs. Call a
change untested only when no check can run, and name the blocker.

When the prompt reports a bug, write the test that reproduces it first, and
watch it fail. Then fix it and watch the test pass.
