# House rules for orchestration agents

Every agent the `/orchestration` router spawns follows these. Your own agent file covers your
job; this file covers how you treat the machine. Where the two disagree, your agent file wins.

The user drives the run from the Claude mobile app and never sees this machine. Every command
that needs approval is a prompt on their phone, and nobody notices what's left on the disk.

## 1. Nothing prompts before the deploy

Everything up to and including the deploy runs only commands that need no approval. That rules
out: `rm` or any other delete, removing worktrees, branches or simulators, `kill`/`pkill`,
`chmod`, `git push`, `gh pr merge`, `git restore`/`reset`/`rebase`, `commit --amend`.

- **Restructure** so you don't need the operation: overwrite a file instead of deleting it,
  `bash script.sh` instead of `chmod +x`. If you can't, **defer** it until after the deploy or
  **report** it. Never prompt for it.
- **Never route around a prompt** with another command: no `commit-tree`, `update-ref`,
  `checkout -B` or `branch -f` to rewrite or move a branch; no `mv` to a trash folder, no
  `find -delete` or `xargs rm`.
- **Review fixes go in a new commit** with a descriptive message. Never amend or rewrite.

## 2. Only the cleaner deletes

Everyone else deletes nothing and lists what they made in `LEFT ON MACHINE`. The cleaner
removes simulators right after the deploy, and everything else once the user has tested.

## 3. One scratch folder

All scratch (logs, build logs, screenshots in `shots/`, temp clones, helper scripts) goes in the
SCRATCH folder from your brief, `<repo>/.orchestration/<slug>/`, which is git-excluded.

- Never `/tmp`, `/private/tmp`, `$TMPDIR` or a bare `mktemp`, and never the worktree.
- A tool that wants a temp folder: `mkdir -p <scratch>/tmp`, then `TMPDIR=<scratch>/tmp`.

## 4. Simulators

Need one? Create your own, named `orch-<slug>-<lane>` (`xcrun simctl create …`). When you're
done, `xcrun simctl shutdown` it and record its UDID in `LEFT ON MACHINE`; the cleaner deletes
it. Never reuse a long-lived simulator, and never boot one for the user to look at: they review
on the deployment.

## 5. Stop what you start

Dev servers, watchers, `log stream`: start them with `run_in_background` and stop them with
`TaskStop`, or use commands that end on their own (`log stream --timeout <n>`). Never `kill`.
A process you can't stop that way goes in `LEFT ON MACHINE` with its PID. A process the user
needs for testing (preview server, tunnel) is marked `held`.

## 6. Clean commits only

- Stage paths by name, never `git add -A`.
- Before committing, `git diff --cached --name-only` lists only the intended source files: no
  scratch, logs, screenshots, `.orchestration/`, `DerivedData/` or temp files.
- A new file slipped in (shows `A` in `git status --short`)? `git rm -r --cached -q <path>`
  unstages it and keeps the file, even mid-merge.
- Anything else wrong in the index: don't commit it, report it.
- No "wip" or fixup commits.

## 7. Report what's left

End every report with `LEFT ON MACHINE:`. List worktrees and branches, shut-down simulator
UDIDs, scratch paths and running PIDs (mark `held` where it applies), or write `nothing`.
That line is the cleaner's inventory.
