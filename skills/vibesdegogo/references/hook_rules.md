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
output redirection or `tee`. A redirection to `/dev/null` writes nothing and so
does not count (`2>/dev/null` silences stderr rather than writing the sidecar);
it is stripped before the check rather than exempting the segment, so a segment
that both silences stderr and writes still shows its `>` and stays denied. Only
`/dev/null` is stripped here — the entry gate's carve-out also covers
`/dev/stdout` and `/dev/stderr`, which is unsafe for this guard: the pattern has
no terminator, so `>/dev/stdout/<sidecar>` would be swallowed whole, and on
Linux `/dev/stdout` is `/proc/self/fd/1`, which `1<.` in the same segment makes
resolve inside the repository. Every other form — interpreters (`python`,
`perl`), `dd`, `install`, `truncate`, other redirects, file ops — is denied.
Segmenting means a `git commit` cannot shield a sidecar-mutating segment in
the same command line.

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
| `investigating` | 3 | only `tasks/vdgg/{id}/` | allow except state writes; reads are logged; 3 -> 4 needs every Related file read | allow |
| `planning` | 4 | only `tasks/vdgg/{id}/` | allow except state writes; 4 -> 5 needs verbatim plan excerpts | allow |
| `task-selected` | 5 | block | allow except state writes | allow |
| `implementing` | 6 | only task notes (implementation files change through `vdgg_patch_apply` / `vdgg_codemod_apply`) | block commits and test commands; 6 -> 7 needs an intact patch chain | allow |
| `testing` | 7 | only task notes (review fixes go through reflection and a patch) | block commits, direct testing to implementing, and verified without review gate + task gate + plan reconciliation | allow |
| `reflection` | 6-R | only `progress.md` and `investigation-r*.md` | block direct verified and require updated retry docs before implementing | allow |
| `verified` | 7 end | block | allow except state writes | allow |
| `progress` | 8 | only `progress.md` and configured version files | allow except state writes | allow |
| `commit` | 9 | only `progress.md` and configured version files | allow commit; block base branch commit/push in branch-pr | allow |

## Evidence Gates

The shared library `scripts/vdgg-evidence.sh` (byte-identical in both editions) holds the checks; the hooks call them at the transitions below.

- **Step 3 -> 4, read evidence.** While `investigating`, the hook appends the files the agent reads to `.claude/.vdgg-read-{id}`: Read/Grep/Glob/LS/NotebookRead targets, and the files a Bash reader names (`cat`, `less`, `head`, `tail`, `nl`, `diff`, `grep`, `rg`, `sed`, `awk`, `git show|diff|log|blame`, `< file`). The command is tokenized with shell quoting, `#` comments and here-documents in mind; the first positional argument of a pattern-first reader (grep, rg, sed, awk) is its pattern, not a file. At `vdgg_state_advance 4 planning` every path listed under `## 1. Related files` must exist and appear in the log; a directory counts when anything under it was read.
- **Step 4 -> 5, plan evidence.** At `vdgg_state_advance 5 task-selected`, or `vdgg_task_begin` from `planning`, every `## T<n>` task in `todo.md` needs `### Location`, `### Excerpt` and `### Intent`. Each excerpt must appear verbatim, as consecutive lines, in the named file (`新規`/`new` only for a file that does not exist), and a code block outside an Excerpt is refused. `progress.md` must exist.
- **Step 6, patch first.** In `implementing`, Edit/Write on implementation files is refused. `vdgg_patch_apply` and `vdgg_codemod_apply` are the only helpers that advance the patch chain `.claude/.vdgg-task-patchchain-{id}`, a content snapshot of the allowlisted files. At `vdgg_state_advance 7 testing` the chain must hold at least one apply, and the files must still match its last snapshot. `vdgg_task_begin` and `vdgg_task_rollback` restart the chain; a new loop keeps it, so a change made outside a patch in `testing` or `reflection` still blocks the next 6 -> 7 until it is rolled back. Edit/Write on implementation files is refused in `testing` too. Patches may not touch protected paths (`.claude/.vdgg-*`, `.codex/.vdgg-*`, `.vdgg-target`, `.git/`) or symlinks.
- **Step/phase pairing.** `vdgg_state_write` accepts each step only with its own phases (3 investigating, 4 planning, 5 task-selected, 6 implementing|reflection, 7 testing|verified, ...) and each phase only after its predecessor in the workflow (`testing` from `implementing`, `reflection` from `testing`, `verified` from `testing`, `progress` from `verified`, `task-selected` from `planning` or `progress`). The hooks refuse a transition whose step and phase are not literal words (a variable, an escape, a quote), and match the rest on word boundaries. Together these leave the gated transitions as the only way out of each phase.
- **Step 7, plan reconciliation.** At `vdgg_state_advance 7 verified`, a task that is in `todo.md` needs a non-empty `Plan reconciliation: <task>` section in `progress.md`. A task id that is neither in `todo.md` nor a `TF` followup is refused.

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
- The read whitelist is a leading-verb model, so read-only forms it does not name are denied: `sed -n '1,5p' <sidecar>`, `awk '{print}' <sidecar>`, and `for f in <sidecar>*; do …; done` are all blocked. `sed` and `awk` are left out deliberately (`sed -i`, and awk's `print > "file"`, write); `for` is extracted as the leading verb but is not on the list. The denial message names representative allowed verbs, so read such a file with `cat`/`head`/`grep` instead.
- The redirect test looks for a redirect operator in the same segment, not at where the redirect points. A read that redirects its output to an ordinary file is therefore denied (`cat <sidecar> > /tmp/copy`), while the same read piped onward is allowed (`cat <sidecar> | tee /tmp/copy`), because the pipe starts a new segment that no longer mentions the sidecar. Neither form writes the sidecar; `cat x | tee <sidecar>` is still denied, since `tee` is not on the read list. Carving out more redirect targets is not the fix — see the `/dev/null` note under Common Guards.
- The entry gate's Bash write detection shares the same literal-match limits: interpreter one-liners (`python -c "open('f','w')"`), writes hidden behind shell variables, `>|` (noclobber overwrite, split away with `|` during segmenting), and a bare trailing `>` left at a segment end are not detected. It stops contract-ignoring drift (the observed failure mode), not a deliberately evasive agent.
- Beyond the evidence gates above, Step 3 and Step 4 artifacts (`investigation-r*.md`, the prose of `investigation.md` and `todo.md`) are not validated by the hooks. What the hooks enforce is narrower: `requirements.md` must exist and carry a non-empty `## Lessons Applied` heading before Step 2 -> Step 3, the reflection gate compares file mtimes, and the evidence gates check what they name. Reading a file shallowly still passes the read gate.
- Read evidence is recorded when the hook sees the call (PreToolUse), not when the command succeeds: a reader that fails or never runs (`false && cat f`) still counts. Reads the tokenizer cannot see (variables, command substitution, `xargs`, loops, paths after a `cd`) are not recorded, so they make the gate stop, never pass. The gate stops skipped reading; it does not prove comprehension.
- The patch chain detects changes to allowlisted files made outside the helpers; it cannot tell a deliberate hand edit run through `vdgg_codemod_apply` from a codemod. The count check catches runaway substitutions, not intent.
