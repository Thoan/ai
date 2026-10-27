# ai-skills

Reusable skills, prompts and notes for working with AI coding agents. Organized
by harness so the repo can grow beyond a single tool or model.

## Layout

```
skills/
  <skill-name>/SKILL.md     # Claude Code skills (YAML frontmatter + markdown)
harnesses/                  # (as they're added) per-harness ports and notes
  <harness>/<skill-name>/
docs/                       # model- and harness-specific tips, tradeoffs
```

Only `skills/` exists today. When a skill is ported to another harness or tuned
for a different model, it goes in `harnesses/<harness>/` next to a short note on
what changed and why.

## Skills

| skill | harness | what it does |
|---|---|---|
| [`orchestration`](skills/orchestration/SKILL.md) | Claude Code | Main thread acts as a pure router: plan, fan out to subagents in git worktrees, review, integrate, land. The main thread never does the work itself. |

### Installing a Claude Code skill

Copy the skill folder into your user or project skills directory:

```sh
cp -r skills/orchestration ~/.claude/skills/        # all projects
cp -r skills/orchestration .claude/skills/          # one project
```

`orchestration` expects subagents named `planner`, `researcher`, `implementer`,
`implementer-opus`, `reviewer`, `integrator` and `lander` in `~/.claude/agents/`.
See the roster table in the skill for what each one is for.

## Contributing / reuse

MIT licensed — use it at work, fork it, change it. See [LICENSE](LICENSE).
