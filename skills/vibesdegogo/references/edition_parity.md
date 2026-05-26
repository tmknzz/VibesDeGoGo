# Claude and Codex Edition Parity

VibesDeGoGo! has two maintained editions:

- `skills/vibesdegogo/`: Claude Code edition.
- `.agents/skills/vibesdegogo/`: Codex edition.

They share the same workflow contract, but they are not byte-for-byte copies.
Each edition is tuned for the hook surface, tool names, and state directory used
by its host environment.

## Intentional Differences

| Area | Claude Code edition | Codex edition |
| --- | --- | --- |
| State directory | `.claude/` | `.codex/` |
| Skill path assumption | `$HOME/.claude/skills/vibesdegogo` | repo `.agents/skills/vibesdegogo` or `$HOME/.codex/skills/vibesdegogo` |
| Review gate | `simplify` skill sentinel | `vdgg_state_mark_reviewed` sentinel |
| Helper style | More verbose, fail-safe oriented shell | Shorter shell helpers for Codex workflow use |
| Hook targets | Claude Code tool names such as Bash, Edit, Write, Agent, Skill | Codex hook matchers such as Bash, apply_patch, Edit, Write |

## Must Stay In Sync

Keep these contracts aligned in both editions:

- Step numbers and phase names.
- Allowed state transitions, including `8 -> 5` and `7 -> 6`.
- State file format: KEY=VALUE fields for `step`, `phase`, `loop_count`,
  `current_task`, `vdgg_id`, and `last_updated`.
- Public helper API names and argument shapes: `vdgg_state_init`,
  `vdgg_state_read`, `vdgg_state_write`, `vdgg_state_advance`,
  `vdgg_state_loop`, `vdgg_state_clear`, `vdgg_get_id`, and related accessors.
- Direct state-file edit blocking.
- Branch/PR safety policy for the default `branch-pr` workflow.
- Reflection requirement after failed verification or review changes.

## May Differ

These implementation details may differ when the host environment justifies it:

- Internal helper structure.
- Comment style and error message wording.
- Hook matcher syntax and tool names.
- Sentinel implementation details that are private to one host.
- Setup instructions for the host's global or project-local hook registration.

## Change Checklist

Before merging a workflow, state, or hook change:

- Decide whether the change affects the shared workflow contract.
- If it does, update both editions or document why one edition is not affected.
- Run syntax checks for both script sets.
- Run smoke tests when available.
- Update this parity note when a new intentional difference is introduced.
