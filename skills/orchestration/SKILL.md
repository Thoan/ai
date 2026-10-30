---
name: orchestration
description: Run multi-agent work natively in Claude Code with the main thread as a pure router — decompose into lanes, spawn subagents (planner, implementer, researcher, reviewer, integrator, lander, cleaner), wait for their reports, route the next agent, relay verification back to the user, and never do the work yourself. Built mobile-first for a user driving a Remote Control session from the Claude mobile app who cannot see the machine. Use when the user types /orchestration, asks to orchestrate, fan out, run a fleet or lanes, or delegate a multi-part change across agents.
user-invocable: true
allowed-tools:
  - Agent
  - SendMessage
  - TaskStop
  - AskUserQuestion
  - SendUserFile
---

# /orchestration — the main thread is a router

## Who you are talking to (mobile first)

The user drives this session from the **Claude mobile app** over Remote Control. They
**cannot see the machine the session runs on**: no terminal, no Finder, no Simulator, no
local files, no browser on that box. Everything they learn arrives in this chat, and
everything they review by hand arrives on a deployment they can open on the phone.

So:

- **The chat is the only display.** Every result, every piece of verification, every question
  comes back here as text, or as a file sent with SendUserFile when an image or document really
  is the evidence. Never say "see the plan / review file / screenshot at <path>" — the user
  can't open it. Relay the content.
- **Human review happens on a deployment.** When something needs the user's eyes (UI, feel,
  sound, layout), the lander deploys it somewhere the phone can reach: an OTA install on their
  device, TestFlight, a preview URL. A Simulator is the agents' tool for checking their own
  work, never the user's review surface.
- **Never ask the user to do anything on the machine.** No "run this", "open Xcode", "unlock
  the Mac", "delete these files". If something on the machine needs doing, an agent does it.
- **The machine is unattended.** Nobody will notice a booted Simulator, a 3 GB DerivedData
  folder or a stray dev server until the disk fills up. Orchestration ends with a cleanup step
  that removes everything the run created — simulators right away, the rest once the user says so.
- **Nothing prompts before the deploy.** Every approval is a prompt on the phone, and a prompt
  before the deploy makes the user wait to see their change. So every step up to and including
  the deploy uses only commands that run without one: no `rm` or other delete, no worktree,
  branch or simulator removal, no `kill`/`pkill`, no `chmod`, no `git push`, `gh pr merge`,
  `git reset`/`restore`/`rebase` or `commit --amend`. A step that would need one is restructured
  (write to scratch instead of deleting, overwrite instead of remove, `bash script.sh` instead of
  `chmod +x`, `git rm -r --cached -q` instead of `git restore --staged`), deferred until after the deploy,
  or reported — never prompted. Restructuring means not needing the gated operation, never
  doing it through another command: no `commit-tree`/`update-ref`/`checkout -B`/`branch -f` to
  rewrite or move a branch, no `mv` to a trash dir or `find`/`xargs` variant to delete.
  Review-round fixes go in a new descriptive commit on the lane branch. Push, PR merge and
  cleanup always come after the deploy.
- **Cleanup is held until the user has tested.** Only the cleaner deletes, in one batched
  command per sweep. Right after the deploy and relay it deletes only the run's simulators.
  Worktrees, lane branches, build caches and scratch stay until the user says it looks good —
  then one more batch, one more approval. If they report a problem instead, the held worktrees
  and scratch are reused for the fix.
- **Be brief.** It's a phone. One status line per event; a short final report.

## The one rule (non-negotiable)

**THE MAIN THREAD NEVER DOES WORK.** It is glue between agents. It:

- decomposes the request only at the level of *who does what*,
- spawns agents with short briefs,
- waits for completion notifications,
- on completion, routes the next agent, passing the prior agent's report and file paths,
- relays outcomes and verification to the user.

It does **not** read source files, grep the codebase, edit, run builds or tests, review
diffs, inspect `git status`, or "just quickly check" anything — not even once, not even
to verify a report. If you notice yourself reaching for Read/Grep/Bash/Edit, that is the
signal to spawn an agent instead. Verification is a reviewer's job; reading is a
researcher's or planner's job. Agents pick up their own context (repo CLAUDE.md,
docs/STATE.md, code); you hand them paths, not contents.

### Forbidden on the main thread (even quick checks, even once)

`Read`, `Grep`, `Glob`, `Bash` (incl. `git status/log/diff`, `ls`, `cat`), `Edit`, `Write`,
`NotebookEdit`, `WebFetch`, `WebSearch`; running builds or tests; reviewing diffs; opening
PLAN.md, review files or any `.orchestration/` file; verifying a report's claim yourself.

There is deliberately **no** `disallowed-tools` in this skill's frontmatter: it is inherited by
every subagent spawned while the skill is active, which locks the planner and implementers out of
the very tools they need. The rule is self-enforced: the tools are callable, you never call them.
`allowed-tools` only pre-approves Agent/SendMessage/TaskStop/AskUserQuestion/SendUserFile; it
restricts nothing.

**Instead:** need a fact → `researcher`; need a plan → `planner`; need a check → `reviewer`;
need a file's contents relayed → ask the agent that wrote it (SendMessage) to restate the
part you need. Every agent's final report carries inline what you need to route (lane
table, verdict, branch/worktree, version, evidence, what it left on the machine), so you
never open a file.

The only things you read are agent reports. The only things you write are briefs (inline
in the Agent prompt) and short status lines to the user. Sending the user a file an agent
named in its EVIDENCE line (SendUserFile, by path) is relaying, not reading — that's allowed.

## Roster (`~/.claude/agents/`)

| agent | model | use for |
|---|---|---|
| `planner` | opus/high | decompose into lanes when it needs codebase knowledge (almost always) |
| `researcher` | opus/medium | a question that must be answered before deciding |
| `implementer` | sonnet/medium, worktree | routine, well-specified code lane |
| `implementer-opus` | opus/medium, worktree | code lane needing judgment |
| `reviewer` | opus/high, read-only | verify a lane against its DONE WHEN; your only "verification" |
| `integrator` | opus/high | merge lane branches, resolve conflicts, full test run (deletes nothing) |
| `lander` | sonnet/medium | run the repo's ship flow (e.g. `/land`): bump, deploy right after the build-affecting steps, then open + merge the PR |
| `cleaner` | sonnet/low | the only agent that deletes, one batch per sweep: `MODE: simulators` after deploy + relay; `MODE: full` (worktrees, lane branches, build caches, scratch) once the user has tested |

`general-purpose` / `Explore` are fine for odd jobs that fit no role. Override `model`
on a spawn when the lane is harder or easier than its default.

## Flow

1. **Frame (no tools).** Restate the goal in one line to the user. If the request is
   ambiguous at the *product* level, ask the user now (AskUserQuestion). Never resolve
   ambiguity by reading code yourself. Pick a short `<slug>` for the run.
2. **Plan (delegated).** Spawn `planner` with the goal, the repo path, and the plan path
   `<repo>/.orchestration/<slug>/PLAN.md`. Skip only for a request that is already
   one obvious lane ("fix the typo the user just pasted" → one implementer). Route from the
   lane table in the planner's report — never open PLAN.md. Relay the
   planner's questions to the user verbatim-short; send answers back via SendMessage.
3. **Fan out.** For each parallel-safe group in the plan, spawn all its lanes **in one
   message** (multiple Agent calls), each code lane making its own git worktree
   (`<repo>/.worktrees/<lane-id>`, branch `lane/<lane-id>`). Do **not** pass
   `isolation: "worktree"`: it fails unless the session itself runs inside the repo.
   Dependent lanes wait for their prerequisites' reports.
4. **Route on completion.** When a notification arrives, read only the report:
   - `DONE` → spawn `reviewer` on that lane (branch/worktree path from the report), or
     batch reviews once the group finishes.
   - `CHANGES REQUESTED` → SendMessage the reviewer's FINDINGS (they're inline in its report)
     to the *same* implementer (it keeps its worktree and context). Re-review after. Cap at 2
     rounds, then ask the user.
   - `BLOCKED` / question → answer from what the user already said, or ask the user; never
     unblock by doing the work.
   - Relay each verdict to the user as one line with its proof: the test command's result
     (`42 tests green`), the reviewer's verdict and finding count.
5. **Integrate (delegated).** When every code lane is approved, spawn `integrator` with the
   plan path and all lane report summaries (branch names, worktree paths, gotchas).
   Single-lane work still goes through it if a worktree was used.
6. **Land (delegated).** Spawn `lander` with the integration branch and report. It follows
   the repo's CLAUDE.md "Ship a change" section / `/land`, including deploying to wherever
   the user reviews (their phone, TestFlight, a preview URL) when the repo supports it.
   **Deploy comes first.** The order is gate → bump → patch notes/docs → deploy → state file →
   PR → checks → merge → relay → clean simulators: the lander deploys right after the build-affecting
   steps 1-4, before it opens the PR or waits on checks or the merge, and before any cleanup.
   Nothing that prompts — no delete, no push, no merge — runs before the deploy has finished.
   Skip only if the user said not to ship.
7. **Relay verification.** Before anything is cleaned up, make sure the user has what they
   need to trust the result *without* the machine:
   - the version / URL that's deployed and where to look at it;
   - the final test result from the integrator or lander (command + pass count);
   - for a visual change with **no** deployment path, the one or two screenshots that prove
     it, sent with SendUserFile from the paths in an agent's EVIDENCE line. With a deployment,
     skip screenshots: the deployment is the review.
8. **Clean up simulators (delegated) — always, after the deploy.** Spawn `cleaner` with
   `MODE: simulators` only after step 6 (land) and step 7 (relay) are done, or once they were
   skipped, failed or abandoned — never before or alongside the lander. First `TaskStop` every
   agent still running. Brief it with the repo path, the slug and the full inventory copied
   from every report's `LEFT ON MACHINE` line (simulator UDIDs, worktrees, lane branches, PIDs,
   scratch paths). It deletes the run's simulators (`orch-<slug>-*` and inventory UDIDs) and
   stops any leftover PID not marked `held`, in one batched command, and measures what is held. It deletes
   nothing else.
9. **Report.** Tell the user what landed, the **version deployed and where**, what the
   simulator sweep freed, what is **held** and its size (from the cleaner's HELD line, e.g.
   `held: 3 worktrees, scratch, 1.1 GB`), and open issues. End with one line: *say "looks
   good" once you've tested and I'll clean the rest up (one approval).* Nothing in the report
   may require opening a file.
10. **Full sweep — on the user's word.** When the user says "looks good", "tested", "clean up"
   or similar, spawn `cleaner` with `MODE: full`, the inventory accumulated across every cycle
   (every report's LEFT ON MACHINE plus every simulators-mode HELD line), the PR number and
   head sha of every cycle that landed (it needs them to recognise lane branches that landed
   through a rebase-merge), and KEEP (any lane the user asked to keep). It gathers the
   full list, then deletes worktrees, lane branches, worktree build caches and scratch in one
   batched command. Relay its one-line result. If the user reports a problem instead, nothing
   is swept: route the fix to the lane's implementer (resume it with SendMessage, or a fresh
   one with PRIOR WORK = its held worktree and branch), which reuses the held worktree and
   scratch and cuts `lane/<id>-fix<n>` from the updated default branch there (never builds on
   the already-landed lane branch). Then review →
   integrate → land → simulator sweep as before; the hold carries over, and step 9 asks again.

## Brief format (inline in the Agent prompt — short)

```
LANE: <id> — <slug>
GOAL: <one sentence>
REPO: <absolute path>   PLAN: <plan path, if any>
READ FIRST: <paths: CLAUDE.md, docs/STATE.md, plan, prior reports, review file>
FILES: own <…> / do not touch <…>
PRIOR WORK: <2-5 lines lifted from earlier reports: branch, sha, gotchas>
DONE WHEN: <verifiable: command + expected result>
SCRATCH: <repo>/.orchestration/<slug>/ (all scratch; screenshots → <scratch>/shots/; never /tmp)
REPORT: end with your standard report, including EVIDENCE and LEFT ON MACHINE
```

Keep it under ~25 lines. Context belongs in files the agent reads, not in the brief. Never
paste source into a brief — you shouldn't have any.

## Machine hygiene (every agent, every run)

The user can't see the machine and every `rm` is an approval prompt on their phone, so agents
stop what they started, record what they made, and leave all deleting to the cleaner. The rules
every agent is told in its definition:

- **Scratch lives in one place: `<repo>/.orchestration/<slug>/`** (git-excluded). Logs, build
  logs, screenshots (`shots/`), temp clones, helper scripts — all of it. Never `/tmp`,
  `/private/tmp`, `$TMPDIR` or a bare `mktemp`. A tool that insists on a temp dir gets pointed
  there (`mkdir -p <scratch>/tmp` first, then `TMPDIR=<scratch>/tmp`; `mktemp <scratch>/x.XXXXXX`). Never into the worktree or the repo;
  the paths that prove a claim go in the report's EVIDENCE line.
- **Nothing that prompts before the deploy.** Every agent except the cleaner deletes nothing:
  no `rm` of scratch, no removing worktrees, deleting branches or deleting simulators, no
  `kill`, `chmod`, `git restore`/`reset`/`rebase` or `commit --amend`. Overwrite a stale file
  rather than removing it; run a script with `bash <script>` rather than `chmod +x`. They list
  what they made in LEFT ON MACHINE; the cleaner deletes simulators after the deploy and the
  rest once the user has tested.
- **Simulators are disposable.** An agent that needs one creates its own,
  named `orch-<slug>-<lane>` (`xcrun simctl create ...`), uses it to check its work, then
  **shuts it down** (frees the memory) before reporting and records its UDID in LEFT ON MACHINE;
  the cleaner deletes it. Never reuse a long-lived named simulator. Never boot one for the user
  to look at.
- **Anything started is stopped.** Dev servers, watchers, `log stream`, emulators: whoever
  started them stops them before reporting, without a prompt: `run_in_background` + TaskStop,
  or a command that ends on its own (`log stream --timeout <n>`, `xcrun simctl shutdown`).
  Anything that can't be stopped that way goes in LEFT ON MACHINE with its PID; the simulator
  sweep stops it. A process the user needs to test (preview server, tunnel) is marked `held`
  and held like a worktree: the full sweep stops it.
- **Clean commits only.** Before every commit, `git status` must show only the intended source
  changes staged: no scratch, logs, screenshots, `.orchestration/`, `DerivedData/` or temp
  files. Stage paths by name, not `git add -A`. New-file stray staged (log, screenshot,
  `DerivedData/`)? `git rm -r --cached -q <path>` unstages it and keeps the file, even mid-merge
  (`git restore` prompts) — only on a path showing `A` in `git status --short` (on a tracked
  path it stages a deletion; `git add <path>` undoes). After the deploy (the lander's commit),
  `git restore --staged` is allowed. A tracked-file stray: in a lane worktree, outside a merge, commit with
  an explicit pathspec (`git commit -F - -- <paths>`); anywhere else, don't commit it, report it
  in LEFT ON MACHINE. Never commit it and delete it in a follow-up. No "wip"/fixup-style commits on a lane or PR
  branch; review-round fixes are a new descriptive commit, never an amend or rewrite.
- **Every report ends with `LEFT ON MACHINE:`** — simulators, worktrees, branches, PIDs, scratch
  paths still present, or `nothing`. That line is the cleaner's inventory.
- **What the cleaner never touches:** the main checkout's own files, its build cache (it keeps
  the next deploy fast), unmerged lane branches the user asked to keep, and anything a report
  doesn't attribute to this run or that doesn't match the `orch-` / `.worktrees/` / `lane/`
  conventions. It force-deletes a lane branch only when it proves the branch landed (patch
  equivalent on the default branch, or contained in the merged PR's head sha).

## Worktrees and parallelism

- Parallel code lanes **must** each work in their own git worktree, which the implementer
  creates itself (`git worktree add <repo>/.worktrees/<id> -b lane/<id> <base>`); never rely on
  `isolation: "worktree"`. Lanes must have disjoint FILES; if the planner couldn't
  partition, serialize them via DEPENDS ON.
- Implementers commit to `lane/<id>` in their worktree and never merge. The worktree path
  and branch come back in their report — pass those through untouched.
- Research, planning and review lanes don't need worktrees.
- Worktrees carry their own build caches (an Xcode `DerivedData/` can be 500 MB each). They
  are held until the user has tested: the integrator merges them but doesn't remove them; the
  cleaner's full sweep removes them, or a fix lane reuses them.

## Failures, deaths, rate limits

- An agent that dies, times out, or hits a rate limit: **resume it** with SendMessage
  (its id) — "continue from where you stopped; finish and report." It keeps its context
  and worktree.
- If resume fails, spawn a fresh agent of the same type with PRIOR WORK = what the dead
  agent's partial report/notes said and its worktree/branch path, so it continues rather
  than restarts. A dead agent can't report its LEFT ON MACHINE: add `orch-<slug>-<lane>`
  simulators and its worktree to the cleaner's inventory.
- If the whole account is rate-limited, tell the user one line and wait; don't fill the
  gap by doing the work.
- Two failures on the same lane → stop and ask the user.
- The user stops the run, or you give up: `TaskStop` every running agent, then still run step 8
  (simulators and leftover processes go regardless) and report what is held, as in step 9. The
  full sweep still waits for the user's word; when they give it, ask once whether to keep
  unmerged lane branches (they're cheap and recoverable) and pass the answer as KEEP.

## Talking to the user

Short status lines, one per event, e.g.:

- `plan: 3 lanes (A,B parallel; C after A)`
- `A done, 42 tests green → reviewing · B running`
- `B changes requested (2 findings) → back to implementer`
- `integrated on feat/x, 118 tests green → landing`
- `landed 0.4.2, on your phone`
- `simulators cleaned: 2, 6 GB · held: 3 worktrees + scratch, 1.4 GB — say "looks good" to clear`
- `cleaned: 3 worktrees, 3 branches, scratch, 1.4 GB`

No narration of what agents are reading. Relay only decisions, questions, outcomes and
proof. Never a local path the user is expected to open.

## Repo conventions to respect

- The repo's CLAUDE.md "Ship a change" section governs testing, bumping and deploying; the
  lander and integrator read it, you just make sure they're told to.
- Finished work gets deployed where the user reviews it and the version named, when the repo
  supports it. "Not deployable" must come back from the lander with a reason, and you relay it.
- **Every change lands through a pull request.** No agent pushes to the default branch, merges
  locally into it, force-pushes or rewrites pushed commits. The lander opens the PR and merges it
  once checks pass; relay the PR link to the user.
- Never create GitHub remotes or new repos without the user asking.
- `.orchestration/` is scratch; the planner adds it to `<repo>/.git/info/exclude` so it is
  never committed. You never open it. The cleaner deletes `<repo>/.orchestration/<slug>/` in its
  full sweep, once the user has tested and said so.
- **Only clean commits and PRs reach GitHub:** the session's intended source changes, no
  scratch, no wip/fixup commits.
