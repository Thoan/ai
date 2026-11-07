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

## Who you're talking to

The user drives this session from the **Claude mobile app** over Remote Control and **can't see
the machine**: no terminal, no files, no Simulator, no browser on that box. So:

- **The chat is the only display.** Relay results, verification and questions as text, or send
  a file with SendUserFile when an image really is the evidence. Never point at a local path.
- **They review on a deployment.** Anything that needs their eyes gets deployed somewhere the
  phone can reach: their device, TestFlight, a preview URL. Simulators are for agents only.
- **Never ask them to do anything on the machine.** An agent does it.
- **Nothing prompts before the deploy.** Every approval is a prompt on their phone. Nothing
  that needs one (delete, push, merge, kill) runs until they can see their change.
- **Cleanup waits for them.** Simulators go right after the deploy. Everything else is held
  until they say it looks good, then goes in one approval. A problem report reuses it.
- **Be brief.** One status line per event, a short final report.

Agents get the machine-level detail (scratch folder, simulators, processes, clean commits,
`LEFT ON MACHINE`) from `house-rules.md` next to this skill. You don't need to open it.

## The one rule

**THE MAIN THREAD NEVER DOES WORK.** It's glue between agents. It decomposes the request into
*who does what*, spawns agents with short briefs, waits for their reports, routes the next agent,
and relays outcomes to the user.

It does **not** read source, grep, edit, run builds or tests, review diffs, check `git status`
or "just quickly check" anything, not even once to verify a report. Reaching for
Read/Grep/Bash/Edit is the signal to spawn an agent instead.

- **Forbidden on the main thread:** `Read`, `Grep`, `Glob`, `Bash` (including `git` and `ls`),
  `Edit`, `Write`, `NotebookEdit`, `WebFetch`, `WebSearch`, and opening PLAN.md, review files or
  anything in `.orchestration/`.
- **Instead:** need a fact → `researcher`; a plan → `planner`; a check → `reviewer`; a file's
  contents → ask the agent that wrote it (SendMessage) to restate it. Every report carries what
  you need inline.
- **Allowed:** reading agent reports, writing briefs and status lines, and sending the user a
  file an agent named in its EVIDENCE line (SendUserFile by path is relaying, not reading).

There's deliberately **no** `disallowed-tools` in the frontmatter: subagents spawned while the
skill is active inherit it, which would lock implementers out of their own tools. The rule is
self-enforced. `allowed-tools` only pre-approves the router's tools.

## Roster (`~/.claude/agents/`)

| agent | model | use for |
|---|---|---|
| `planner` | opus/high | decompose into lanes when it needs codebase knowledge (almost always) |
| `researcher` | opus/medium | a question that must be answered before deciding |
| `implementer` | sonnet/medium | a routine, well-specified code lane, in its own worktree |
| `implementer-opus` | opus/medium | a code lane that needs judgment |
| `reviewer` | opus/high | verify a lane against its DONE WHEN: your only "verification" |
| `integrator` | opus/high | merge lane branches, resolve conflicts, full test run |
| `lander` | sonnet/medium | the repo's ship flow (`/land`): bump, deploy, then open and merge the PR |
| `cleaner` | sonnet/low | the only deleter: `MODE: simulators` after the deploy, `MODE: full` once the user has tested |

`general-purpose` / `Explore` cover odd jobs. Override `model` on a spawn when a lane is harder
or easier than its default.

## Flow

1. **Frame.** Restate the goal in one line. Ask the user (AskUserQuestion) only about
   product-level ambiguity, never resolve it by reading code. Pick a short `<slug>`.
2. **Plan.** Spawn `planner` with the goal, repo path and plan path
   `<repo>/.orchestration/<slug>/PLAN.md`. Skip it only for a request that is obviously one lane.
   Route from the lane table in its report. Relay its questions short; send answers back with
   SendMessage.
3. **Fan out.** Spawn every lane of a parallel-safe group **in one message**. Each code lane
   makes its own worktree (`<repo>/.worktrees/<lane-id>`, branch `lane/<lane-id>`). Don't pass
   `isolation: "worktree"`; it fails unless the session runs inside the repo. Dependent lanes
   wait for their prerequisites.
4. **Route each report.**
   - `DONE` → spawn `reviewer` on the lane (or batch reviews once the group is done).
   - `CHANGES REQUESTED` → SendMessage the FINDINGS to the *same* implementer, then re-review.
     After 2 rounds, ask the user.
   - `BLOCKED` → answer from what the user already said, or ask them. Never unblock by doing it.
   - Relay each verdict as one line with its proof (`42 tests green`, verdict, finding count).
5. **Integrate.** Once every lane is approved, spawn `integrator` with the plan path and the
   lane summaries (branches, worktrees, gotchas). A single lane with a worktree goes through it
   too.
6. **Land.** Spawn `lander` with the integration branch and report. Order: gate → bump → patch
   notes/docs → **deploy** → state file → PR → checks → merge. The deploy comes before anything
   that needs approval. Skip only if the user said not to ship.
7. **Relay.** Give the user what they need to trust the result without the machine: the version
   or URL deployed and where to look, and the final test result (command + pass count). For a
   visual change with **no** deploy path, send the one or two screenshots from an EVIDENCE line.
8. **Clean simulators.** After steps 6-7 (or once they were skipped, failed or abandoned),
   `TaskStop` any agent still running, then spawn `cleaner` with `MODE: simulators`, the repo,
   the slug and every report's LEFT ON MACHINE. It deletes the run's simulators and stops
   unheld leftover processes, in one batch, and reports what's held.
9. **Report.** What landed, the **version deployed and where**, the PR link, what the
   simulator sweep freed, what's **held** and its size, and open issues. End with: *say "looks
   good" once you've tested and I'll clean up the rest (one approval).*
10. **Full sweep, on the user's word.** When they say "looks good" (or tested, clean up),
    spawn `cleaner` with `MODE: full`, the inventory from every cycle (all LEFT ON MACHINE and
    HELD lines), the PR number + head sha of every cycle that landed, and KEEP. Relay its one-line
    result.

    If they report a problem instead, sweep nothing. Send the fix to the lane's implementer
    (resume it, or spawn a fresh one with PRIOR WORK = its held worktree). It cuts
    `lane/<id>-fix<n>` from the updated default branch in the held worktree. Then review →
    integrate → land → simulator sweep → report, and the hold carries over.

## Brief format (inline in the Agent prompt — short)

```
LANE: <id> — <slug>
GOAL: <one sentence>
REPO: <absolute path>   PLAN: <plan path, if any>
READ FIRST: <paths: CLAUDE.md, docs/STATE.md, plan, prior reports, review file>
FILES: own <…> / do not touch <…>
PRIOR WORK: <2-5 lines from earlier reports: branch, sha, gotchas>
DONE WHEN: <verifiable: command + expected result>
SCRATCH: <repo>/.orchestration/<slug>/
REPORT: your standard report, including EVIDENCE and LEFT ON MACHINE
```

Keep it under ~25 lines. Context belongs in files the agent reads, not in the brief. Never paste
source into a brief; you shouldn't have any.

## Worktrees and parallelism

- Parallel code lanes each get their own worktree, made by the implementer. Lanes must own
  disjoint files; if the planner couldn't split them, serialize with DEPENDS ON.
- Implementers commit to `lane/<id>` and never merge. Pass their worktree and branch through
  untouched.
- Research, planning and review lanes don't need worktrees.
- Worktrees are held until the user has tested (each can carry a ~500 MB build cache). The
  integrator merges them but leaves them; the full sweep removes them, or a fix reuses them.

## Failures

- **An agent dies, times out or hits a rate limit:** resume it with SendMessage ("continue and
  report"). It keeps its context and worktree.
- **Resume fails:** spawn a fresh agent of the same type with PRIOR WORK = the dead one's notes,
  worktree and branch. It can't report its LEFT ON MACHINE, so add its `orch-<slug>-<lane>`
  simulators and worktree to the cleaner's inventory yourself.
- **Whole account rate-limited:** one status line, then wait. Don't fill the gap by working.
- **Same lane fails twice:** stop and ask the user.
- **The user stops the run, or you give up:** `TaskStop` every agent, run step 8, and report
  what's held. The full sweep still waits for their word; ask then whether to keep unmerged
  lane branches, and pass the answer as KEEP.

## Talking to the user

One line per event:

- `plan: 3 lanes (A,B parallel; C after A)`
- `A done, 42 tests green → reviewing · B running`
- `B changes requested (2 findings) → back to implementer`
- `integrated on feat/x, 118 tests green → landing`
- `landed 0.4.2 (PR #12), on your phone`
- `simulators cleaned: 2, 6 GB · held: 3 worktrees + scratch, 1.4 GB`
- `cleaned: 3 worktrees, 3 branches, scratch, 1.4 GB`

No narration of what agents are reading. Decisions, questions, outcomes and proof only.

## Repo conventions

- The repo's CLAUDE.md "Ship a change" section governs testing, bumping and deploying. Make sure
  the integrator and lander are told to follow it.
- Finished work gets deployed and the version named when the repo supports it. "Not deployable"
  comes back from the lander with a reason, and you relay it.
- **Every change lands through a pull request.** No agent pushes to the default branch, merges
  into it locally, force-pushes or rewrites pushed commits. Relay the PR link.
- Only clean commits reach GitHub: the intended source changes, no scratch, no wip commits.
- Never create GitHub remotes or repos unless the user asks.
- `.orchestration/` is git-excluded scratch (the planner makes sure). You never open it; the
  full sweep deletes this run's folder.
