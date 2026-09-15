# VibesDeGoGo! Reference: Hook Rules

This file documents the behavior implemented by the hooks.

## Common Guards

Sidecar files are protected. Edit/Write tools targeting any path matching:

```text
.claude/.vdgg-*
```

are blocked outright. Bash commands are split into shell segments (on `&&`, `||`,
`;`, `|`, newline) and each segment that mentions a sidecar path is checked with
a **whitelist** (fail-closed): the segment is allowed only if it is a `git commit`
(whose message may mention a sidecar path without writing it) or a genuine read —
a leading read-only verb (`cat`, `grep`, `test`, `ls`, `head`, `tail`, …) with no
output redirection or `tee`. Every other form — interpreters (`python`, `perl`),
`dd`, `install`, `truncate`, redirects, file ops — is denied. Segmenting means a
`git commit` cannot shield a sidecar-mutating segment in the same command line.

This covers state files, the active marker, and the simplify/review sentinels —
so the review gate cannot be satisfied by forging a sentinel. Use `vdgg_state_*`
helpers instead. The same write protection also applies to `.vdgg-target`
(reads stay allowed), so the agent cannot self-author `REVIEW_COMMAND` to forge
a passing review.

## Phase Behavior

| phase | Step | Edit/Write | Bash | Agent |
|---|---:|---|---|---|
| no state | none | allow (deny when `VDGG_REQUIRED=on`) | allow (deny writes/commits when `VDGG_REQUIRED=on`) | allow |
| `declare` | 1 | only `tasks/vdgg/{id}/` | allow except state writes | block |
| `requirements` | 2 | only `tasks/vdgg/{id}/` | require `requirements.md` before Step 3 | block |
| `investigating` | 3 | only `tasks/vdgg/{id}/` | allow except state writes | allow |
| `planning` | 4 | only `tasks/vdgg/{id}/` | allow except state writes | allow |
| `task-selected` | 5 | block | allow except state writes | allow |
| `implementing` | 6 | only task-allowlisted files (task notes exempt) | block commits and test commands | allow |
| `testing` | 7 | only task-allowlisted files (task notes exempt) | block commits, direct testing to implementing, and verified without review gate + task gate | allow |
| `reflection` | 6-R | only `progress.md` and `investigation-r*.md` | block direct verified and require updated retry docs before implementing | allow |
| `verified` | 7 end | block | allow except state writes | allow |
| `progress` | 8 | only `progress.md` and configured version files | allow except state writes | allow |
| `commit` | 9 | only `progress.md` and configured version files | allow commit; block base branch commit/push in branch-pr | allow |

## Entry Gate (VDGG_REQUIRED)

While no session is armed (no `.claude/.vdgg-active`, empty id, or missing
state file), the hooks are normally fail-open. When the repository's
`.vdgg-target` sets `VDGG_REQUIRED=on` (the literal value `on` only), the
PreToolUse hook instead denies, until `vdgg_state_init` arms a session:

- `Edit` / `Write` / `NotebookEdit` on any path (including `.vdgg-target`
  itself, so the gate cannot be self-disabled),
- unknown tools that expose a `file_path` / `notebook_path` (fail-closed),
- Bash segments that write files: redirects to real paths (`>` / `>>`;
  redirects to `/dev/null`, `/dev/stdout`, `/dev/stderr` and fd dups like
  `2>&1` are exempt), `tee`, a leading mutating verb (`rm`, `mv`, `cp`, `dd`,
  `install`, `truncate`, `touch`, `ln`, `patch`, `mkfifo`), `sed`/`perl`
  with `-i`, or `git commit`.

Read-only tools, `Agent` (a subagent's own tool calls pass through this same
hook), builds/tests, and the arming command itself stay allowed. Without jq
the hook cannot classify tools, so it fails closed while the key is `on`
(only jq installation commands pass). Absent/`off`/other values keep the
historical fail-open behavior, so repositories that never opted in are
untouched.

Rationale: arming the gates must not be a voluntary act. An agent that
ignores the workflow contract (observed 2026-07-05: a model invoked the
skill, never ran `vdgg_state_init`, and committed directly) would otherwise
keep every guard dormant. The deny message points to Step 1.

## Error Recognition

PostToolUse detects Bash failures and writes:

```text
.claude/.vdgg-error-pending
```

The next Bash command must contain the marker in its command text (e.g. in a
leading comment), the same contract as the Codex edition:

```text
[Error Acknowledged]
```

The agent should briefly state what failed and what it will do next.

Search commands such as `rg`, `grep`, `find`, `sed`, `awk`, `jq`, `test`, and `[` are treated specially: exit code 1 is allowed as "no matches".

## Review Gate (simplify or explicit review)

This section is the authoritative specification of the enforced review gate.
SKILL.md Step 7 provides the agent-facing review procedure and additional review
obligations. Its requirements for reviewer perspectives and handling findings
remain applicable; they are not all enforced by hooks.

During `testing`, successful verification must be followed by a review pass.
Two sentinels can satisfy the gate:

```text
.claude/.vdgg-simplify-sentinel-{vdgg_id}-{loop_count}   created by PostToolUse when the simplify skill runs
.claude/.vdgg-review-sentinel-{vdgg_id}-{loop_count}     created by vdgg_review_run when the review command exits 0
```

When both exist for the current id and loop, PreToolUse reads the simplify
sentinel and ignores the review one.

### Sentinel fields

`_vdgg_render_sentinel_body` in `vdgg-state.sh` is the only writer of the field
order and key names. Both sentinel kinds carry the same nine lines; a value that
does not apply is written as an empty string rather than an omitted line:

```text
started=1
started_at=<UTC timestamp>
modified=0|1
modified_files=<comma-separated paths>
review_output_hash=<sha256 of the review output, or empty>
lens_count=<reviewer perspective count, or empty>
countersign=none|clean|refuted
schema_validated=0|1
countersign_required=0|1
```

A sentinel whose last five fields are all absent or empty is classified `legacy`
(written before those fields existed) and skips the Layer-4 invariants below.

### What vdgg_review_run checks

`vdgg_review_run [--review-output <file>] [--] <command>` runs the command first
and propagates its exit status on failure. A sentinel is written only after the
command exits 0. Writing a sentinel is not the same as opening the gate: the
verified conditions below are checked separately, at gate-read time.

With `--review-output <file>`:

- Layer 1 (`_vdgg_validate_review_output`) requires a JSON object with array
  `coverage` and `findings`. Each coverage entry needs `file`, `hunk_start`,
  `hunk_lines`, and `judgment` (`ok` or `finding`). Each finding needs `file`,
  `line`, `severity` (`high`/`medium`/`low`), `summary`, `fix`, and `cost`
  (`low`/`medium`/`high`). The coverage entries must also overlap every hunk of
  the current diff.
- Layer 2 (`_vdgg_validate_review_lens_count`) requires a top-level `lens_count`
  of at least 3. A missing, non-numeric, or negative value sanitizes to 0 and
  fails. This is a floor, not the Step 7 target: Step 7 asks for more
  perspectives on a large or contract-changing diff, and no hook checks that.
- The sentinel then records the output's sha256 as `review_output_hash`, the
  sanitized `lens_count`, `schema_validated=1`, `countersign=none`, and
  `countersign_required=0` when the primary review produced a high or medium
  finding, `1` when it did not.

Without `--review-output` (the legacy path), neither layer runs. The sentinel
records `schema_validated=0`, an empty hash and lens_count, and
`countersign_required=1`, so the gate stays closed until a countersign is
recorded. The legacy path cannot reach verified on its own.

### What the simplify sentinel records

PostToolUse writes it when the `simplify` skill is invoked during `testing`,
through the same renderer, with `review_output_hash` and `lens_count` empty,
`countersign=none`, `schema_validated=0`, and `countersign_required=0`. No
Layer 1 or Layer 2 check backs it. Simplify's own parallel angle finders supply
the perspective diversity, and the hook records nothing about them, so SKILL.md
Step 7's account of simplify describes agent behavior, not a hook check.

### What vdgg_review_countersign changes

`vdgg_review_countersign --original-output <a> --countersign-output <b> <command>`
returns 0 without running the command when the original already holds a high or
medium finding. Otherwise it runs the command, applies Layer 1 and Layer 2 to
the countersign output, and returns 1 when the countersign surfaces a high or
medium finding the original missed. On success it rewrites the sentinel with the
original's hash and lens_count, `countersign=clean`, `schema_validated=1`, and
`countersign_required=1` left as it was.

### Verified transition behavior

PreToolUse blocks a `vdgg_state_*` command that moves to `verified` unless all of
the following hold:

- when a task allowlist is armed and its file exists, the current loop's task
  gate file exists (`vdgg_task_gate` succeeded),
- a simplify or review sentinel exists for the current id and loop,
- that sentinel's `modified` is not `1`,
- `_vdgg_validate_sentinel_fields` accepts it: `schema_validated=1` requires a
  non-empty `review_output_hash` and a non-zero `lens_count`;
  `schema_validated=0` together with a non-zero `lens_count` is contradictory;
  `countersign` must be one of `none`/`clean`/`refuted`; `countersign_required`
  must be `0`, `1`, or empty,
- `_vdgg_review_gate_ready` accepts it: `countersign_required=1` requires
  `countersign=clean`.

On success both sentinels are deleted so one review pass cannot satisfy a later
loop. `modified=1` blocks the transition and requires reflection plus a re-test.
PostToolUse sets `modified=1` on whichever sentinel exists when Edit/Write
touches implementation files during `testing` (sidecar paths and
`tasks/vdgg/{id}` are excluded). Sentinels cannot be written through tool calls;
see Common Guards. `_vdgg_write_review_sentinel` additionally refuses any call
that does not carry the one-shot `_VDGG_WRITE_REVIEW_SENTINEL_AUTHORIZED=1`
breadcrumb, which closes the shortcut of calling the writer directly.

Acting on the review's own findings — fixing the high and medium issues, judging
what is genuinely out of scope — is the agent's obligation under SKILL.md Step 7.
No hook checks it. A review whose findings were ignored still opens the gate as
long as the fields above line up.

## Known Limits

- The Stop hook depends on Claude Code providing `cwd` and `transcript_path` in hook JSON. If Claude Code changes that contract, the Stop hook may become a no-op rather than a blocker.
- The reflection gate compares whole-second file mtimes; if `progress.md` or `investigation-r*.md` is written in the same second as the state transition, the return to implementing can be blocked once — retrying a moment later succeeds.
- The sidecar write guard matches the literal `.claude/.vdgg-` path in the Bash command text. A segment that hides the path behind a shell variable or command substitution (e.g. `D=.claude; rm -f "$D/.vdgg-active"`) can evade the match. The hook raises the cost of forgery but is a guardrail, not a security boundary; it does not sandbox a determined agent.
- The entry gate's Bash write detection shares the same literal-match limits: interpreter one-liners (`python -c "open('f','w')"`), writes hidden behind shell variables, `>|` (noclobber overwrite, split away with `|` during segmenting), and a bare trailing `>` left at a segment end are not detected. It stops contract-ignoring drift (the observed failure mode), not a deliberately evasive agent.
- Step 3 and Step 4 artifacts (`investigation-r*.md`, plan files under `tasks/vdgg/{id}/`) are not structurally validated by the hooks. What the hooks enforce is narrower: `requirements.md` must exist and carry a non-empty `## Lessons Applied` heading before Step 2 -> Step 3, and the reflection gate compares file mtimes. Everything else about those artifacts relies on the agent's own inspection.
