# shellcheck shell=bash
# Helpers the mise tasks source from the repo root, where mise runs them.
# It sits outside .mise/tasks/, so mise doesn't list it as a task.

# Prints the tracked fish scripts. Scripts without a .fish extension count
# through their shebang.
fish_files() {
  git ls-files '*.fish'
  git grep -lE '^#!/usr/bin/env (-S )?fish' -- modules setup
}

# Prints the tracked shell scripts. Tracked files only, so node_modules
# and scratch directories stay out.
shell_files() {
  git ls-files -z | xargs -0 shfmt -f
}

fail() {
  echo "$1" >&2
  exit 1
}

# Sets tmp to a new directory under the checkout's .claude/tmp/, named
# after $1, and removes it on exit. A shared temp directory leaks files
# between the accounts on a machine, and git ignores .claude/. A fresh
# checkout, as in CI, lacks .claude/tmp/. A failed jj or git command in
# it walks up to this repo, so a test that runs either needs a directory
# outside the checkout.
scratch() {
  mkdir -p .claude/tmp
  tmp=$(mktemp -d "$PWD/.claude/tmp/$1.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
}
