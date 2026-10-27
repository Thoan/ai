---
name: orchestration
description: Run multi-agent work natively in Claude Code with the main thread as a pure router — decompose into lanes, spawn subagents (planner, implementer, researcher, reviewer, integrator, lander), wait for their reports, route the next agent, and never do the work yourself. Use when the user types /orchestration, asks to orchestrate, fan out, run a fleet or lanes, or delegate a multi-part change across agents.
user-invocable: true
allowed-tools:
  - Agent
  - SendMessage
  - TaskStop
  - AskUserQuestion
---

# /orchestration — the main thread is a router

## The one rule (non-negotiable)

**THE MAIN THREAD NEVER DOES WORK.** It is glue between agents. It:

- decomposes the request only at the level of *who does what*,
- spawns agents with short briefs,
- waits for completion notifications,
- on completion, routes the next agent, passing the prior agent's report and file paths.

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
`allowed-tools` only pre-approves Agent/SendMessage/TaskStop/AskUserQuestion; it restricts nothing.

**Instead:** need a fact → `researcher`; need a plan → `planner`; need a check → `reviewer`;
need a file's contents relayed → ask the agent that wrote it (SendMessage) to restate the
part you need. Every agent's final report carries inline what you need to route (lane
table, verdict, branch/worktree, version), so you never open a file.

The only things you read are agent reports. The only things you write are briefs (inline
in the Agent prompt) and short status lines to the user.

## Roster (`~/.claude/agents/`)

| agent | model | use for |
|---|---|---|
| `planner` | opus/high | decompose into lanes when it needs codebase knowledge (almost always) |
| `researcher` | opus/medium | a question that must be answered before deciding |
| `implementer` | sonnet/medium, worktree | routine, well-specified code lane |
| `implementer-opus` | opus/medium, worktree | code lane needing judgment |
| `reviewer` | opus/high, read-only | verify a lane against its DONE WHEN; your only "verification" |
| `integrator` | opus/high | merge lane branches, resolve conflicts, full test run, clean worktrees |
| `lander` | sonnet/medium | run the repo's ship flow (e.g. `/land`): version bump, merge, push |

`general-purpose` / `Explore` are fine for odd jobs that fit no role. Override `model`
on a spawn when the lane is harder or easier than its default.

## Flow

1. **Frame (no tools).** Restate the goal in one line to the user. If the request is
   ambiguous at the *product* level, ask the user now (AskUserQuestion). Never resolve
   ambiguity by reading code yourself.
2. **Plan (delegated).** Spawn `planner` with the goal, the repo path, and the plan path
   `<repo>/.orchestration/<slug>/PLAN.md`. Skip only for a request that is already
   one obvious lane ("fix the typo the user just pasted" → one implementer). Route from the
   lane table in the planner's report — never open PLAN.md. Relay the
   planner's questions to the user verbatim-short; send answers back via SendMessage.
3. **Fan out.** For each parallel-safe group in the plan, spawn all its lanes **in one
   message** (multiple Agent calls), each code lane making its own git worktree (`<repo>/.worktrees/<lane-id>`, branch `lane/<lane-id>`). Do **not** pass `isolation: "worktree"`: it fails unless the session itself runs inside the repo.
   Dependent lanes wait for their prerequisites' reports.
4. **Route on completion.** When a notification arrives, read only the report:
   - `DONE` → spawn `reviewer` on that lane (branch/worktree path from the report), or
     batch reviews once the group finishes.
   - `CHANGES REQUESTED` → SendMessage the review file path to the *same* implementer (it
     keeps its worktree and context). Re-review after. Cap at 2 rounds, then ask the user.
   - `BLOCKED` / question → answer from what the user already said, or ask the user; never
     unblock by doing the work.
5. **Integrate (delegated).** When every code lane is approved, spawn `integrator` with the
   plan path and all lane report summaries (branch names, worktree paths, gotchas).
   Single-lane work still goes through it if a worktree was used.
6. **Land (delegated).** Spawn `lander` with the integration branch and report. It follows
   the repo's CLAUDE.md "Ship a change" section / `/land`. Skip only if the user said not to
   ship.
7. **Report.** Tell the user what landed, the **version shipped**, and open issues.

## Brief format (inline in the Agent prompt — short)

```
LANE: <id> — <slug>
GOAL: <one sentence>
REPO: <absolute path>   PLAN: <plan path, if any>
READ FIRST: <paths: CLAUDE.md, docs/STATE.md, plan, prior reports, review file>
FILES: own <…> / do not touch <…>
PRIOR WORK: <2-5 lines lifted from earlier reports: branch, sha, gotchas>
DONE WHEN: <verifiable: command + expected result>
REPORT: end with your standard report; write long output to <repo>/.orchestration/<slug>/<lane>.md
```

Keep it under ~25 lines. Context belongs in files the agent reads, not in the brief. Never
paste source into a brief — you shouldn't have any.

## Worktrees and parallelism

- Parallel code lanes **must** each work in their own git worktree, which the implementer creates itself
  (`git worktree add <repo>/.worktrees/<id> -b lane/<id> <base>`); never rely on `isolation: "worktree"`. Lanes must have disjoint FILES; if the planner couldn't
  partition, serialize them via DEPENDS ON.
- Implementers commit to `lane/<id>` in their worktree and never merge. The worktree path
  and branch come back in their report — pass those through untouched.
- Research, planning and review lanes don't need worktrees.

## Failures, deaths, rate limits

- An agent that dies, times out, or hits a rate limit: **resume it** with SendMessage
  (its id) — "continue from where you stopped; finish and report." It keeps its context
  and worktree.
- If resume fails, spawn a fresh agent of the same type with PRIOR WORK = what the dead
  agent's partial report/notes said and its worktree/branch path, so it continues rather
  than restarts.
- If the whole account is rate-limited, tell the user one line and wait; don't fill the
  gap by doing the work.
- Two failures on the same lane → stop and ask the user.

## Talking to the user

Short status lines, one per event, e.g.:

- `plan: 3 lanes (A,B parallel; C after A)`
- `A done → reviewing · B running`
- `B changes requested (2 findings) → back to implementer`
- `integrated on feat/x, tests green → landing`
- `landed 0.4.2`

No narration of what agents are reading. Relay only decisions, questions, and outcomes.
Keep it scannable.

## Repo conventions to respect

- The repo's CLAUDE.md "Ship a change" section governs testing, bumping and deploying; the
  lander and integrator read it, you just make sure they're told to.
- Never create GitHub remotes or new repos without the user asking.
- `.orchestration/` is scratch; the planner adds it to `<repo>/.git/info/exclude` so it is
  never committed. You never touch it. Pass file paths through in briefs; never open them.
