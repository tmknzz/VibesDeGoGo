# VibesDeGoGo! Reference: State Helpers

The state helper script is:

```bash
source $HOME/.claude/skills/vibesdegogo/scripts/vdgg-state.sh
```

## Files

```text
.claude/.vdgg-active
tasks/vdgg/{id}/
.claude/.vdgg-state-{id}
```

State file format:

```text
step=<number>
phase=<phase>
loop_count=<number>
current_task=<task title>
vdgg_id=<YYYYMMDD-HHMM-xxxx>
last_updated=<UTC timestamp>
```

## Public Functions

```bash
vdgg_state_init
vdgg_state_read
vdgg_state_write <step> <phase> <loop_count> [current_task]
vdgg_state_advance <step> <phase>
vdgg_state_loop <step> <phase>
vdgg_state_clear
vdgg_get_tasks_dir
vdgg_get_id
```

## Transition Rules

Allowed transitions:

- same step,
- next step,
- `8 -> 5` to continue with unfinished tasks,
- `7 -> 6` for testing/reflection retry.

`vdgg_state_loop` increments `loop_count` and removes the old simplify sentinel for that loop.

`8 -> 5` resets `loop_count` to 0 because a new task starts.

## Cleanup

`vdgg_state_init` and `vdgg_state_clear` remove stale transient files:

```text
.claude/.vdgg-error-pending
.claude/.vdgg-step-block-*
.claude/.vdgg-simplify-sentinel-*
```

## Simplify Sentinel

Path:

```text
$CWD/.claude/.vdgg-simplify-sentinel-{vdgg_id}-{loop_count}
```

Fields:

```text
started=1
started_at=<UTC timestamp>
modified=0|1
modified_files=<comma-separated paths>
```

Lifecycle:

1. Created by PostToolUse when the `simplify` skill runs during `testing`.
2. Updated to `modified=1` when Edit/Write runs after simplify in the same loop.
3. Deleted when verified transition succeeds, loop advances, or state clears.
