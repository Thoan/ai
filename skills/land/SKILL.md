---
name: land
description: Close out a work session in any project — test, bump the version, deploy, write patch notes, refresh the state file, then commit, merge to the default branch and push. Use when the user types /land or says to ship it, land it, wrap up, or deploy the current work.
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# /land — ship the session's work

The project-agnostic version of the per-repo `*-land` skills. Run the steps **in order** —
the version bump is gated on a green build, and the deploy is gated on the bump.

**`/land` means land it.** Invoking this skill *is* the authorization to commit, merge and
push. Don't stop at a commit and offer the merge; don't ask whether to push. The only reason
not to finish is the user explicitly saying "don't push."

Work in the session's cwd (or a project the user names). Use absolute paths.

## 0. Read the repo's own recipe first

Everything project-specific comes from the repo, not from this file:

- **`CLAUDE.md`** — look for a **"Ship a change"** section. If it exists, *it wins* over
  every default below: its test command, its device IDs, its bump rule, its invariants.
  Some repos' CLAUDE.md just points at their own `/xx-land` skill — if so, use that skill
  instead and say so.
- **The state file** — `docs/STATE.md`, else `STATE.md`.

If the repo has no shipping recipe at all, derive what you can (step 1), do the parts that
apply, and **say plainly which steps you skipped and why**. Don't invent a deploy.

## 1. Gate on a green build

Find the test command, in this order: the `CLAUDE.md` recipe → an obvious project runner
(`package.json` scripts, `Makefile`, `Cargo.toml`, `pytest.ini`, an `.xcodeproj`/`project.yml`)
→ ask.

For a generated Xcode project, regenerate **only** if `project.yml` changed or a source file
was added or removed:

```sh
xcodegen generate
xcodebuild test -scheme <Scheme> -destination 'platform=macOS' 2>&1 | tail -30
```

Long builds auto-background; redirect to a log and poll rather than chaining `sleep`:
`... > /tmp/land.log 2>&1`, then loop until the log matches
`TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)`.

**Red → stop and fix.** Never bump, never deploy, never merge on red. If a test is expected
red and the user has said so, name it explicitly in the report rather than quietly passing.

## 2. Bump the version

Find the constant the app actually displays — grep for `gameVersion`, `appVersion`,
`APP_VERSION`, `MARKETING_VERSION`, or the `version` field in `package.json`/`Cargo.toml`.
Prefer the one shown in the UI over the one in the build settings; that's the one that makes
a fresh build verifiable at a glance.

Default rule, unless `CLAUDE.md` says otherwise: **patch-sized change → last component +1;
a real feature may take the minor.** If the repo's history shows a `0.x` line that never
rolls to `1.0` (after `0.99` comes `0.100`), respect it — **`1.0` is the user's call alone.**

Bump *after* the green build, never speculatively.

## 3. Patch notes

If the repo has a changelog the user reads — `PatchNotes.swift`, `CHANGELOG.md`,
`Releases.swift` — add an entry at the **top**: the new version, today's date, one emoji, a
short title, and 3–6 bullets.

**Player voice, not changelog voice.** Say what changed for the person using it, not which
function was refactored. If the repo has no changelog and the project is user-facing, offer
to start one; don't create one silently.

## 4. Make the docs match the code

Every repo has invariants that go stale quietly. Read the **Invariants** section of
`CLAUDE.md` and check this change against each one — that section exists precisely because
those are the things that break without failing a build.

Then grep for anything this change made stale:

```sh
grep -rn '<old term>' <source dir> --include='*.<ext>'
```

If the repo has a test that enforces a doc invariant (a docs-match-code test, a snapshot, a
generated-file check), that test passing in step 1 **is** this step for that invariant. Say
which invariant it covered.

## 5. Deploy

Use the `CLAUDE.md` recipe verbatim if there is one. **A green build is the cue — don't wait
to be asked.**

For an iOS project with no recipe, discover the device rather than guessing:

```sh
xcrun devicectl list devices          # get the UDID and the identifier
```

then build → install → launch, and confirm the launch actually succeeded.

**A locked phone is not a failure.** `FBSOpenApplicationErrorDomain error 7 (Locked)` means
the build succeeded, the install succeeded, and *only* the auto-launch was declined. Report
it plainly in this shape and keep going:

> Build green, `<version>` installed on the phone. The auto-launch was declined because the
> device is locked — nothing wrong with the build. Unlock and tap the icon, or say the word
> and I'll re-run the launch.

Do **not** rebuild, reinstall, retry in a loop, hunt for a workaround, call the deploy
failed, or apologise for it.

## 6. Refresh the state file — the part that makes the next session cheap

This is the whole point of the skill. Update:

- **Shipped** — version, test count, whatever this repo tracks there.
- **The live systems** — only if this change moved them.
- **Dormant** — move anything this change retired or revived.
- **Next up** — delete what got done; add what this change exposed, **including anything you
  consciously left out of scope**.
- **In flight** — reset it to `**Nothing — the tree is clean and it's safe to `/clear`.**`
  (keep any HTML comment beneath it). Landing is what clears a parked handoff.

Then ask yourself: *if I read only `CLAUDE.md` + the state file + `git log -8` next session,
would I have a true picture?* If not, fix the state file until the answer is yes.

## 7. Memory, sparingly

Write a memory only for a **durable convention or a decision with a why** that the repo
doesn't already record. Update an existing memory file rather than adding a near-duplicate.
**Never record "what shipped"** — that's the state file's job.

## 8. Land it

```sh
git add -A && git commit -F -        # subject matching the log's existing style
git checkout <default-branch>
git merge --no-ff feature/<branch> -m "Merge feature/<branch> into <default>"
git push origin <default-branch>
git branch -d feature/<branch>       # only after the merge succeeds
```

- Determine the default branch from `git symbolic-ref refs/remotes/origin/HEAD`, else
  whichever of `main`/`master` exists.
- **One commit** for the session's work. Subject in the log's existing style
  (`git log --oneline -5`). Body: what changed and why, plus any measured numbers.
- Match the repo's merge style from its history — `--no-ff` if that's what it does.
- Already on the default branch with no feature branch? Just commit and push.
- No remote? Commit and merge, skip the push, and say there's nowhere to push to.
- **Stop and report** on a merge conflict or a rejected push. Never force-push, never
  `git reset` someone else's commits away.

Don't also invoke `/cmp` — this step *is* that flow.

## 9. Report

Short. What shipped, what's on the device, what's on the default branch, and **anything left
out of scope** the user needs to weigh in on.
