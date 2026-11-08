---
name: commit
description: Create a commit in a repository
---

# Create a commit in a repository

## Git commits

In a Git repository, run `command git diff` to see the changes and
`command git diff --staged` to see what the index already holds. Stage the files
that belong to the commit with `git add <file>...`. Every change belongs unless
the user names a subset.

## Jujutsu commits

A `.jj` directory in the repository root marks a Jujutsu repository. Jujutsu has
no staging area. Any `jj` command snapshots the working directory, untracked
files included, so ask the user which changed files belong in the change. Run
`jj st` to list the files in the current snapshot and `jj show` to see the diff.
Then run `jj split <file>...` with the commit message in `-m` to commit those
files.

Because of the missing staging area, treat every `jj` command that creates or
edits a change with care. When the user asks to squash changes into the last
commit with `jj squash`, ask which files' changes to squash and run
`jj squash <file>...` with those files.

For more on Jujutsu, see the `jj` skill.

## Common instructions

1. Run the Git or Jujutsu commands that show what belongs in the commit.
2. Never commit plan files under `.claude-notes/`. The global
   `~/.config/git/ignore` file ignores that directory. Plan files stay local.
3. Draft a commit message in the format below. Never include prompt text or
   generated-by attribution.
4. **Always** show the proposed commit message to the user and wait for their
   approval before committing. They may want to edit it first. Don't run the
   commit command until they confirm. Ask through the harness's question tool
   when it has one, such as `AskUserQuestion` in Claude Code, with one question
   per commit. Give each question an "Approve" option whose preview holds the
   full message and the files. The tool's free-text answer takes an edited
   message. Show the message as text and ask when no such tool exists.

## Commit message format

- Subject: use `type: description` or `type(scope): description`. Aim for 50
  characters, with a hard limit of 72 for the whole subject. Follow the
  capitalization the repository already uses, which keeps the type and the
  description lowercase under this format. Use the imperative mood and no final
  period. The subject states what the commit does, such as
  `fix(zsh): restore history`.
- Scope: optional, such as `feat(tmux)` or `fix(zsh)`.
- Body: add one only when the motivation needs explaining. Separate it from the
  subject with a blank line and wrap at 72 characters. Explain why the change
  matters. Keep it brief and don't repeat what the diff shows.
- Footer: put a blank line before it. Use the fields below when they apply.

### Footer fields

- `Breaking-Change:`: describe the incompatible change and any required
  migration.
- `Co-Authored-By: Name <email>`: credit a known coauthor. Use their real name
  and email. Never invent attribution.
- `Refs:`: identify the issues or other work items this commit advances, such as
  a PR, task, or specification. Use known IDs, URLs, or paths from the task
  context, such as `Refs: #123` or `Refs: TEAM-456, docs/spec.md`. Omit this
  field when no related work item exists. Never invent a reference.

## Conventional Commits types

| Type     | When to use                               |
| -------- | ----------------------------------------- |
| feat     | New features                              |
| fix      | Bug fixes                                 |
| refactor | Code improvements with no behavior change |
| docs     | Documentation, including code comments    |
| test     | Add or change tests                       |
| perf     | Performance improvements                  |
| style    | Formatting and lint fixes                 |
| chore    | Maintenance, dependencies, and tooling    |

## Example

```text
fix(zsh): preserve history across sessions

Concurrent shells can overwrite each other's history, losing commands
needed in later sessions.

Refs: #123
```
