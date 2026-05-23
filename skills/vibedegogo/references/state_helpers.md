# VibeDeGoGo! Reference: State Helpers

The state helper script is:

```bash
source $HOME/.claude/skills/vibedegogo/scripts/vdg-state.sh
```

## Files

```text
.claude/.vdg-active
tasks/vdg/{id}/
.claude/.vdg-state-{id}
```

State file format:

```text
step=<number>
phase=<phase>
loop_count=<number>
current_task=<task title>
vdg_id=<YYYYMMDD-HHMM-xxxx>
last_updated=<UTC timestamp>
```

## Public Functions

```bash
vdg_state_init
vdg_state_read
vdg_state_write <step> <phase> <loop_count> [current_task]
vdg_state_advance <step> <phase>
vdg_state_loop <step> <phase>
vdg_state_clear
vdg_get_tasks_dir
vdg_get_id
```

## Transition Rules

Allowed transitions:

- same step,
- next step,
- `8 -> 5` to continue with unfinished tasks,
- `7 -> 6` for testing/reflection retry.

`vdg_state_loop` increments `loop_count` and removes the old simplify sentinel for that loop.

`8 -> 5` resets `loop_count` to 0 because a new task starts.

## Cleanup

`vdg_state_init` and `vdg_state_clear` remove stale transient files:

```text
.claude/.vdg-error-pending
.claude/.vdg-step-block-*
.claude/.vdg-simplify-sentinel-*
```

## Simplify Sentinel

Path:

```text
$CWD/.claude/.vdg-simplify-sentinel-{vdg_id}-{loop_count}
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
