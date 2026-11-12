---
name: papercut
description: Record a problem from the current session in this project's local checklist so the user can fix their setup later. Use when the user asks to note, log, or document a problem for later.
---

# Record a papercut

A **papercut** means a problem in the user's setup that interrupted the session,
such as a denied command, a blocked path, a missing tool, or a skill that
misfired. Record it and return to the task. Leave the fix for later.

## 1. Identify

Take the problem from the user's note. Without a note, take the most recent
failure in the conversation. Collect from the conversation alone:

- The failing command or tool call, and its exact error line.
- The task the session worked on when it failed.
- The place the fix most likely goes. Pick from permissions, tools, hooks,
  skills, and `AGENTS.md`, or write `unknown`.
- The session ID, which names the newest transcript in
  `~/.claude/projects/<working directory, non-alphanumerics as ->/`.

## 2. Append

Append one item to `.claude-notes/papercuts.md` in the repository root, or in
the working directory outside a repository. Create the file with a `# Papercuts`
heading when it doesn't exist. Never commit it.

```md
- [ ] 2026-10-30: `jj abandon` denied while dropping a stray change
  - Error: `Permission to use Bash with command jj abandon kwmsmr has been denied.`
  - Context: cleaning up after a split
  - Fix: permissions, or an alternative in `AGENTS.md`
  - Session: 9f2a05c5-057a-4eb9-b33c-6d8421e2dbd0
```

## 3. Return

Confirm the item in one line, then continue the task the session worked on.
