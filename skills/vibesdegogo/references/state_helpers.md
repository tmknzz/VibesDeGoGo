# VibesDeGoGo! Reference: State Helpers

The state helper script is:

```bash
VDGG_SKILL_DIR="${VDGG_SKILL_DIR:-$HOME/.claude/skills/vibesdegogo}"
source "$VDGG_SKILL_DIR/scripts/vdgg-state.sh"
```

For plugin installs, set `VDGG_SKILL_DIR` to the skill's base directory announced when the skill loads.

## Files

```text
.claude/.vdgg-active
tasks/vdgg/{id}/
.claude/.vdgg-state-{id}
.claude/.vdgg-friction-{id}
```

State file format:

```text
step=<number>
phase=<phase>
loop_count=<number>
current_task=<task title>
task_allowlist_file=<path to active allowlist, empty before vdgg_task_begin>
task_base_ref=<path to baseline git-status snapshot>
vdgg_id=<YYYYMMDD-HHMM-xxxx>
last_updated=<UTC timestamp>
```

## Public Functions

```bash
vdgg_state_init
vdgg_state_read
vdgg_state_write <step> <phase> <loop_count> [current_task] [task_allowlist_file] [task_base_ref]
vdgg_state_advance <step> <phase>
vdgg_state_loop <step> <phase>
vdgg_review_run [review command...]
vdgg_task_begin <task title> <allowed path>...
vdgg_task_changed_files
vdgg_task_check_allowlist
vdgg_task_gate [verification command...]
vdgg_task_rollback
vdgg_state_clear
vdgg_friction_report
vdgg_get_tasks_dir
vdgg_get_id
```

## Task Gate

`vdgg_task_begin` writes the allowlist to
`.claude/.vdgg-task-allowlist-{id}-{loop}`, snapshots the allowlisted files
into `.claude/.vdgg-task-baseline-{id}-{loop}/`, and records a
`git status --porcelain` baseline. During `implementing` and `testing`, the
pretool hook blocks Edit/Write outside the allowlist (task notes under
`tasks/vdgg/{id}/` are exempt). `vdgg_task_gate` re-checks the allowlist
against actual changed files (catching Bash-mediated edits too), runs the
verification command, and writes `.claude/.vdgg-task-gate-{id}-{loop}` on
success — required before `verified` whenever an allowlist is active.
`vdgg_task_rollback` reverts allowlisted changes to the baseline; if files
outside the allowlist changed, it refuses — resolve those manually (e.g.
`git status` + `git checkout -- <file>`) before retrying.

`vdgg_review_run` is the review gate for passes done without the Claude Code
`simplify` skill. It runs the review command — an explicit one, or
`REVIEW_COMMAND` from `.vdgg-target` — and writes a per-loop review sentinel
under `.claude/.vdgg-review-sentinel-{id}-{loop}` with `modified=0` only when
that command exits 0; it is the documented way to write that sentinel. The
verified gate accepts either the
simplify sentinel or this review sentinel; both flip to `modified=1` when
implementation files are edited afterward in the same loop. See `SKILL.md`
Step 7 for the full gate description.

## Transition Rules

Allowed transitions:

- same step,
- next step,
- `8 -> 5` to continue with unfinished tasks,
- `7 -> 6` for testing/reflection retry.

`vdgg_state_loop` increments `loop_count`, removes that loop's simplify and review sentinels, and appends a `loop` event to the friction log.

`8 -> 5` resets `loop_count` to 0 and clears `task_allowlist_file`/`task_base_ref` because a new task starts; `vdgg_task_begin` must run again before the next task's edits. Omitted optional args of `vdgg_state_write` preserve the stored values; a literal `-` clears a task field explicitly.

## Cleanup

`vdgg_state_init` and `vdgg_state_clear` remove stale transient files:

```text
.claude/.vdgg-error-pending
.claude/.vdgg-simplify-sentinel-*
.claude/.vdgg-review-sentinel-*
.claude/.vdgg-task-*  (allowlists, baselines, gate files)
.claude/.vdgg-friction-*
```

`vdgg_state_clear` prints `vdgg_friction_report` to stdout before it removes anything.

## Friction Log

Path:

```text
$CWD/.claude/.vdgg-friction-{vdgg_id}
```

Append-only, one line per event. The leading word is the whole contract with the reader; the fields after it are for Step 6-R and humans:

```text
deny phase=<phase> loop=<loop_count> tool=<tool name> gate=<line of the refusing exit>
stop phase=<phase>
loop phase=<phase>
```

- `deny`: written by the PreToolUse hook's EXIT trap when the hook exits 2 after the session is armed. Refusals that happen before that point (missing `jq`, the `VDGG_REQUIRED` entry gate) are not logged.
- `stop`: written by the Stop hook when it refuses a silent stop.
- `loop`: written by `vdgg_state_loop` when a retry starts. `8 -> 5` resets `loop_count`, so this event, not `loop_count`, is the session-wide retry count.

`vdgg_friction_report` prints `denies=N`, `stops=M`, and `loops=L`, one per line, and prints zeros when no session is armed or nothing has been logged.

Known limits:

- Exit status 2 stands in for "a gate refused". `grep` and `jq` also exit 2 on their own errors, so a hook defect can be logged as a `deny`, and a gate that answered with a JSON permission decision would not be counted.
- `gate` is a line number in the hook as it was when the line was written, and means nothing outside that session.
- Only the Claude Code edition writes this log. The Codex edition's hooks do not.

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
