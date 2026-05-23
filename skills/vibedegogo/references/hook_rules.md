# VibeDeGoGo! Reference: Hook Rules

This file documents the behavior implemented by the hooks.

## Common Guards

State files are protected. The hooks block direct edits to:

```text
.claude/.vdg-state-*
.claude/.vdg-active
```

Use `vdg_state_*` helpers instead.

Step declarations are validated for Bash commands that call:

```text
vdg_state_advance
vdg_state_loop
vdg_state_write
```

The Bash command text must include the matching declaration:

```bash
# [VibeDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
source $HOME/.claude/skills/vibedegogo/scripts/vdg-state.sh && vdg_state_advance 3 investigating
```

For Step 2, `[VibeDeGoGo! Declaration]` is also accepted because it follows Step 1 initialization.

## Phase Behavior

| phase | Step | Edit/Write | Bash | Agent |
|---|---:|---|---|---|
| no state | none | allow | allow | allow |
| `declare` | 1 | only `tasks/vdg/{id}/` | allow except state writes | block |
| `requirements` | 2 | only `tasks/vdg/{id}/` | require `requirements.md` before Step 3 | block |
| `investigating` | 3 | only `tasks/vdg/{id}/` | allow except state writes | allow |
| `planning` | 4 | only `tasks/vdg/{id}/` | allow except state writes | allow |
| `task-selected` | 5 | block | allow except state writes | allow |
| `implementing` | 6 | allow except state files | block commits and test commands | allow |
| `testing` | 7 | allow except state files | block commits, direct testing to implementing, and verified without simplify | allow |
| `reflection` | 6-R | only `progress.md` and `investigation-r*.md` | block direct verified and require updated retry docs before implementing | allow |
| `verified` | 7 end | block | allow except state writes | allow |
| `progress` | 8 | only `progress.md` and configured version files | allow except state writes | allow |
| `commit` | 9 | only `progress.md` and configured version files | allow commit; block base branch commit/push in branch-pr | allow |

## Error Recognition

PostToolUse detects Bash failures and writes:

```text
.claude/.vdg-error-pending
```

Before the next tool call, PreToolUse requires assistant text containing:

```text
[Error Acknowledged]
```

The agent should briefly state what failed and what it will do next.

Search commands such as `rg`, `grep`, `find`, `sed`, `awk`, `jq`, `test`, and `[` are treated specially: exit code 1 is allowed as "no matches".

## Simplify Gate

During `testing`, successful verification must be followed by the `simplify` skill.

PostToolUse creates:

```text
.claude/.vdg-simplify-sentinel-{vdg_id}-{loop_count}
```

Fields:

```text
started=1
started_at=<UTC timestamp>
modified=0|1
modified_files=<comma-separated paths>
```

Verified transition behavior:

- sentinel missing: block verified transition,
- `modified=0`: allow verified transition and delete sentinel,
- `modified=1`: block verified transition and require reflection plus re-test.

## Known Limit

The Stop hook depends on Claude Code providing `cwd` and `transcript_path` in hook JSON. If Claude Code changes that contract, the Stop hook may become a no-op rather than a blocker.
