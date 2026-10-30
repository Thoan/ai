# ai

Reusable skills, agents and notes for working with AI coding agents. The main piece is
**`/orchestration`: multi-agent orchestration that's native to Claude Code and built
mobile-first for Remote Control.** You drive it from the Claude app on your phone, and the
work runs on a machine you never look at.

```
skills/
  orchestration/SKILL.md    # the router: the main thread plans, delegates, relays, never works
  land/SKILL.md             # generic ship flow the lander runs (test → bump → deploy → PR → merge)
agents/                     # the subagent roster the router spawns
  planner.md  researcher.md  implementer.md  implementer-opus.md
  reviewer.md  integrator.md  lander.md  cleaner.md
install.sh                  # copies skills/ and agents/ into ~/.claude (backs up what it replaces)
```

---

## The idea

You're on your phone. Your Mac (or a dev box) is somewhere else, running a Claude Code
session you reach through **Remote Control** from the Claude mobile app. You type "add a pause
menu and fix the score overlay". Then the session:

1. plans the work into **lanes** that can run in parallel,
2. hands each lane to a subagent in its **own git worktree**,
3. has a separate **reviewer** check every lane against a verifiable done-criterion,
4. **integrates** the lanes and runs the full test suite,
5. **lands** the work: bumps the version, **deploys it somewhere your phone can reach**
   (OTA install, TestFlight, a preview URL) right after the build-affecting steps, then opens a pull
   request and merges it once its checks pass. Nothing is ever pushed straight to `main`,
6. **cleans up**, last and in one batch, every simulator, worktree, build cache, screenshot
   and process the run created,
7. sends you a few lines of status: what shipped, which version is on your phone, how many
   tests passed, what was freed.

You never open a terminal, a file or a Simulator. Two things make that work:

- **The main thread is only a router.** It never reads code, runs a command or reviews a
  diff. It spawns agents, reads their reports and decides who goes next. That keeps its
  context small enough to run a long session, and it means every fact you see came from an
  agent's report, with the evidence attached.
- **It assumes you can't see the machine.** Verification comes back to the chat as text
  (test command, pass count, reviewer verdict). When a change needs your eyes, the run
  deploys it where you can look at it. And because nobody is watching the disk, the run
  deletes everything it made — in one batched step at the end, so you approve one prompt, not
  dozens.

It uses only Claude Code's own primitives (skills, subagents in `~/.claude/agents/`,
`Agent`, `SendMessage`, `TaskStop`) and nothing else: no external queue, daemon or
orchestration framework.

## What it looks like on the phone

```
you:  /orchestration add a pause menu, and the score overlay overlaps the notch

claude: goal: pause menu + score overlay safe-area fix, shipped to your phone
        plan: 2 lanes (A pause menu, B overlay fix — parallel)
        A running · B running
        B done, 118 tests green → reviewing
        B approved (0 findings)
        A done, 121 tests green → reviewing
        A changes requested (1 finding: resume doesn't restore timer) → back to implementer
        A approved
        integrated on feat/pause-menu, 121 tests green → landing
        landed 0.42.0, on your phone
        cleaned: 3 simulators, 2 worktrees, 1.3 GB

        Shipped 0.42.0 to your iPhone — open the app, tap ⏸ top-left.
        - Pause menu with resume / restart / quit; timer resumes where it stopped
        - Score overlay now sits below the notch on every device size
        Open: none.
```

Questions the planner can't answer from the code (product decisions) come to you as
`AskUserQuestion` prompts, which you tap through in the app.

---

## How it works

```
                        ┌──────────────────────────────────────────┐
   Claude mobile app ◀──┤  MAIN THREAD = router (this skill)       │
   (Remote Control)     │  reads reports · writes briefs · relays  │
                        └───────┬───────────────▲──────────────────┘
                     brief      │               │   report (inline: status, verification,
                                ▼               │   EVIDENCE, LEFT ON MACHINE)
   ┌─────────┐   ┌──────────────────────────┐   ┌──────────┐   ┌────────────┐   ┌────────┐   ┌─────────┐
   │ planner │ → │ implementer × N (parallel│ → │ reviewer │ → │ integrator │ → │ lander │ → │ cleaner │
   │         │   │ each in .worktrees/<id>) │ ↺ │ per lane │   │ merge+test │   │ deploy │   │ sweep   │
   └─────────┘   └──────────────────────────┘   └──────────┘   └────────────┘   └────────┘   └─────────┘
        ▲ researcher whenever a question must be answered before deciding
```

### The flow

| step | who | what happens | what you see |
|---|---|---|---|
| 1 Frame | router | restates the goal in one line; asks you about product-level ambiguity | the goal, maybe a question |
| 2 Plan | `planner` | reads the repo, writes `.orchestration/<slug>/PLAN.md`, returns a lane table with ready-to-copy briefs | `plan: 3 lanes (A,B parallel; C after A)` |
| 3 Fan out | `implementer` / `implementer-opus` | every lane in a parallel group is spawned in one message; each makes its own worktree + `lane/<id>` branch, implements, runs the real tests, commits | `A running · B running` |
| 4 Review | `reviewer` | runs the tests itself, checks DONE WHEN + repo invariants; findings go back to the same implementer (max 2 rounds) | `A done, 42 tests green → reviewing` |
| 5 Integrate | `integrator` | merges lanes in dependency order, full test run; deletes nothing (worktrees + branches go in its LEFT ON MACHINE) | `integrated on feat/x, 118 tests green` |
| 6 Land | `lander` | runs the repo's ship recipe (`/land`): gate → bump → patch notes/docs → **deploy** → state file → PR → checks → merge. The deploy comes right after the build-affecting steps, before PR waits and any cleanup | `landed 0.4.2 (PR #12), on your phone` |
| 7 Relay | router | makes sure you have the version, where to see it, and the final test result; for a visual change with no deploy path, sends 1–2 screenshots | the proof |
| 8 Clean up | `cleaner` | strictly after land + relay: gathers the full inventory, then deletes the run's simulators, worktrees, lane branches, worktree build caches, scratch, processes in one batched command — **always**, even on an abandoned run | `cleaned: 2 simulators, 1.4 GB` |
| 9 Report | router | what landed, version + where, what was freed, open issues | a few lines |

### The report contract

Agents never hand the router a file to read; each final report is self-contained. The
fields the router uses to route:

| field | from | used for |
|---|---|---|
| `STATUS` / `VERDICT` | every agent | what happens next (review, rework, integrate, ask you) |
| `BRANCH / WORKTREE` | implementers, integrator | passed through untouched to the next agent |
| `VERIFICATION` | implementers, reviewer, integrator, lander | exact command + output tail + pass count, which the router relays to you |
| `EVIDENCE` | implementers, reviewer | screenshot/log paths; the router can send them to your phone with `SendUserFile` |
| `FINDINGS` | reviewer | complete enough to forward to the implementer as-is |
| `VERSION … WHERE` | lander | what's deployed and where you open it |
| `LEFT ON MACHINE` | **every** agent | the cleaner's inventory: simulator UDIDs, worktrees, branches, PIDs, scratch paths |

### Machine hygiene

The run assumes nobody will ever look at the machine, so it doesn't leave anything behind.
And because every delete is an approval prompt on your phone, only one agent deletes, once,
at the end:

- **One scratch dir.** Logs, build logs, screenshots, temp clones and helper scripts all go to
  `<repo>/.orchestration/<slug>/`, which is git-excluded. Never `/tmp`, `$TMPDIR` or a bare
  `mktemp`; tools that need a temp dir get `mkdir -p <scratch>/tmp` first, then `TMPDIR=<scratch>/tmp`
  (`<scratch>` being that dir).
- **No deleting mid-run.** Every agent except the cleaner deletes nothing: no `rm`, no
  removing worktrees, no deleting simulators. They list what they made in `LEFT ON MACHINE`.
- **Simulators are disposable.** Any agent that needs one creates its own,
  named `orch-<slug>-<lane>`, checks its work, then **shuts it down** before reporting (that
  frees the memory) and records its UDID; the cleaner deletes it. Simulators are for agents to
  check their own work. Your review happens on the deployment. (One iPhone simulator is about
  3 GB on disk, and they pile up quickly.)
- **Worktrees** stay until the end of the run; the integrator merges them, the cleaner removes
  them. Each worktree has its own build cache, and an Xcode `DerivedData/` can be ~500 MB.
- **Processes** (dev servers, watchers, `log stream`) are stopped by whoever started them.
- **Deploy first.** The order is gate → bump → patch notes/docs → deploy → state file → PR → checks → merge → relay → clean. The lander deploys right
  after the build-affecting steps; cleanup never runs before it or holds it up.
- **The cleaner** runs strictly after landing and the relay. It gathers the whole inventory
  (`LEFT ON MACHINE` lines plus the naming conventions `orch-*`, `.worktrees/`, `lane/*`), then
  does every deletion in one batched command, so you approve once. It never touches the main
  checkout's files or its build cache, force-deletes a lane branch only when it proves the
  branch landed (rebase-merges rewrite SHAs), and leaves (and reports)
  anything it can't attribute to the run: unmerged work, uncommitted changes, things you
  asked to keep.
- **Clean commits only.** Agents stage intended paths by name and check `git status` before
  committing: no scratch, logs, screenshots, `.orchestration/`, `DerivedData/` or temp files,
  no wip/fixup commits. Only the session's intended commits reach GitHub.

---

## Install

### 1. Prerequisites

- **Claude Code** with access to the models the agents use (`opus`, `sonnet`). Change
  `model:` in `agents/*.md` if you need to.
- **git**. Worktrees need a real repo.
- **Remote Control**, to drive it from the phone. In a Claude Code session on the machine,
  run `/remote-control`, then open that session from the Claude mobile app. (It also works
  fine from a terminal; the mobile-first rules just make it work without one.)
- For iOS projects: Xcode command-line tools (`xcrun simctl`, `xcrun devicectl`) and a
  deploy script that installs onto your device, or a TestFlight lane.

### 2. Copy the skills and agents

```sh
git clone https://github.com/Thoan/ai && cd ai
./install.sh                     # → ~/.claude/skills and ~/.claude/agents (all projects)
./install.sh --project ~/code/my-app   # → my-app/.claude/ (one project only)
```

`install.sh` moves anything it would replace to `~/.claude/backups/<timestamp>/` (outside
the folders Claude Code loads from) and skips files that are already identical. Start a new Claude Code session afterwards so it picks them up.

### 3. Give your repo a ship recipe

The agents get project-specific knowledge from the repo itself, not from this one. They
look for:

| in your repo | used by | why |
|---|---|---|
| `CLAUDE.md` → **"Ship a change"** section | planner, integrator, lander | the test/build command, the bump rule, the deploy command. This is the recipe the lander follows |
| `CLAUDE.md` → **Invariants** | reviewer, lander | what must stay true even when the build is green |
| a **deploy path** your phone can reach (`tools/deploy.sh` OTA to device, TestFlight, preview URL) | lander | the deploy is how you review from the phone; without one, the lander reports "not deployable: why" |
| `docs/STATE.md` (or `STATE.md`) | everyone | what's shipped, what's next, what's in flight |
| a changelog (`CHANGELOG.md`, `PatchNotes.swift`) | lander | where the user-facing notes go |

A minimal "Ship a change" section:

```md
## Ship a change
- Test: `tools/check.sh` (must print CHECK GREEN)
- Bump: `AppVersion.swift` `current`, patch +1 per change
- Deploy: `tools/deploy.sh` (builds, installs on the phone, launches)
- Notes: newest entry at the top of `PatchNotes.swift`
```

If CLAUDE.md names a per-repo land skill (say `/myapp-land`), the lander runs that instead
of the generic `land`.

### 4. Run it

```
/orchestration <what you want>
```

…or just ask in plain words to "orchestrate", "fan out" or "run this as lanes". Say "don't
ship" if you want it to stop after integration. The cleanup step still runs.

---

## The roster

| agent | default model | tools | job |
|---|---|---|---|
| `planner` | opus / high | read + write plan | lanes with disjoint file ownership, dependencies, DONE WHEN, deploy target |
| `researcher` | opus / medium | read + write findings | answers a question before anyone decides; separates verified / claimed / inferred |
| `implementer` | sonnet / medium | full edit | a routine, well-specified lane, in its own worktree |
| `implementer-opus` | opus / medium | full edit | a lane that needs judgment (tricky refactors, concurrency, gnarly bugs) |
| `reviewer` | opus / high | read + run tests | APPROVE / CHANGES REQUESTED / BLOCK, findings with file:line and expected fix |
| `integrator` | opus / high | full edit | merges lanes, fixes mechanical breakage, full test run; deletes nothing |
| `lander` | sonnet / medium | full edit + Skill | runs `/land`: gate, bump, deploy first, notes, state file, PR, merge |
| `cleaner` | sonnet / low | read + Bash | the only deleter: final sweep in one batch, reports what it freed and anything it left on purpose |

The router can override `model` per spawn when a lane is harder or easier than usual.
`general-purpose` / `Explore` cover odd jobs that fit no role.

---

## Design decisions (and why)

- **The router never works.** Once the main thread "just quickly checks" a file, its
  context fills with code, it starts second-guessing reports, and long runs degrade. All
  verification belongs to the reviewer. If the router needs a fact, it spawns a researcher.
- **No `disallowed-tools` in the skill.** Claude Code passes a skill's `disallowed-tools` on to
  every subagent spawned while the skill is active, which would lock implementers out of
  Edit and Bash. The router's restraint is self-enforced. `allowed-tools` only pre-approves
  the router's own tools.
- **Agents make their own worktrees** (`git worktree add <repo>/.worktrees/<id> -b lane/<id>`)
  instead of using `isolation: "worktree"`. Built-in isolation fails when the session wasn't
  started inside the repo, which is common for a Remote Control session started from a parent
  folder.
- **Disjoint file ownership per lane.** The planner partitions files so parallel lanes can't
  conflict. If it can't, it serializes the lanes with DEPENDS ON instead.
- **Rework goes to the same implementer** (via `SendMessage`) so it keeps its context and
  worktree. Two rounds max, then you decide.
- **Deployments, not simulators, for human review.** You're on a phone, and a Simulator on a
  remote Mac is invisible to you. Agents use simulators to check their own work, shut them
  down afterwards, and the cleaner deletes them. Anything you need to see gets deployed.
- **Cleanup is a step of its own and always runs.** Folding it into the lander would skip it
  whenever there's no landing (failed run, "don't ship", user stopped it). The cleaner runs
  in every case.
- **Deploy before cleanup; one deleter, one batch.** Every `rm` is a permission prompt on your
  phone. Agents that delete their own scratch as they go bury you in prompts and make the
  deploy wait behind them. So nobody deletes until the deploy is out and relayed, and then
  the cleaner does it all in one command.

## Failure handling

| situation | what the router does |
|---|---|
| agent dies / times out / hits a rate limit | resumes it with `SendMessage` ("continue and report"); it keeps its context and worktree |
| resume fails | spawns a fresh agent of the same type with the dead one's partial notes, worktree and branch, and adds the dead agent's leftovers to the cleaner's inventory |
| whole account rate-limited | one status line, waits, doesn't start doing the work itself |
| same lane fails twice | stops and asks you |
| you stop the run / it's abandoned | stops running agents first, then still runs the cleaner (in one batch). Asks once whether to keep unmerged lane branches; worktrees, simulators and processes are removed either way |

## Customizing

- **Models / effort:** edit `model:` and `effort:` in `agents/*.md`.
- **Non-iOS projects:** nothing to change. The simulator rules only apply when an agent uses
  one; the cleaner skips simulator steps on machines without `xcrun`. Android emulators,
  Docker containers and dev servers fall under the same rule: name it after the run, stop
  it, report it in `LEFT ON MACHINE`.
- **Your own deploy target:** it all comes from your repo's "Ship a change" section. The
  lander deploys to whatever that section describes.
- **Keep a lane's work:** tell the router "keep lane B". It goes into the cleaner's KEEP
  list.

## Troubleshooting

- **Agents aren't found** → they must be in `~/.claude/agents/` (or the project's
  `.claude/agents/`), and the session must have started after you installed them.
- **"isolation: worktree" errors** → something passed it. The skill tells the router not to,
  and the implementers create worktrees themselves.
- **Lander says "not deployable"** → your repo's CLAUDE.md has no deploy step the lander can
  run. Add one (see the ship recipe above).
- **Leftovers from before these rules** (simulators without the `orch-` prefix, old
  `.worktrees/`, stray `.orchestration/` folders) → the cleaner deliberately won't touch what
  it can't attribute to a run. Ask the session for a one-off sweep: list them with sizes
  first, then delete what you approve.

## Contributing

`main` is protected: **every change goes through a pull request**, and nothing can be pushed
to it directly, force-pushed or deleted, by anyone, the owner included. A PR can merge only when
the `sensitive-check` workflow passes. It fails on:

- a commit whose author or committer email isn't a GitHub noreply address,
- added content with an email address (other than GitHub/Anthropic noreply), a local home path
  like `/Users/<name>`, or an Apple device / simulator id,
- secrets, via [gitleaks](https://github.com/gitleaks/gitleaks). GitHub secret scanning with
  push protection is also on.

PRs merge by rebase, so commits land exactly as written.

To catch these before you push, enable the bundled pre-commit hook once per clone:

```sh
git config user.email "<id>+<login>@users.noreply.github.com"   # github.com/settings/emails
git config core.hooksPath .githooks                               # runs scripts/check-sensitive.sh
```

## License / reuse

MIT licensed. Use it at work, fork it, change it. See [LICENSE](LICENSE). When a skill is
ported to another harness or tuned for a different model, put it in `harnesses/<harness>/`
with a short note on what changed and why.
