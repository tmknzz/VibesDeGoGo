#!/bin/bash
# test-evidence-gates.sh — Claude Code edition: the evidence gates of
# docs/proposals/2026-09-24-evidence-gates.md, driven through the real
# PreToolUse hook (JSON in, exit code out) and the real state helpers.
#   1. Step 3 -> 4: every Related file exists and was read while investigating.
#   2. Step 4 -> 5: todo.md tasks carry a verbatim excerpt of the current code.
#   3. Step 6: patch first; 6 -> 7 needs the patch chain intact.
#   4. Step 7: verified needs a Plan reconciliation record for planned tasks.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/sentinel-fixtures.sh"
. "$ROOT/tests/lib/req-fixtures.sh"

PRETOOL="$ROOT/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
TASKS="$T/tasks/vdgg/test-id"
READ_LOG="$T/.claude/.vdgg-read-test-id"

write_state() {
    local phase="$1" step="$2" task="${3:-T}" allowlist="${4:-}"
    mkdir -p "$T/.claude" "$TASKS"
    printf 'test-id\n' > "$T/.claude/.vdgg-active"
    cat > "$T/.claude/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=0
current_task=${task}
task_allowlist_file=${allowlist}
task_base_ref=
vdgg_id=test-id
last_updated=2026-09-24T00:00:00Z
EOF
}

run_hook() {
    printf '%s' "$1" | bash "$PRETOOL" >/dev/null 2>"$T/hook.err"
    # zsh: $status is read-only, so the exit code goes to rc.
    local rc=$?
    printf '%s\n' "$rc"
}

bash_json() {
    jq -nc --arg c "$1" --arg cwd "$T" '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$c}}'
}

tool_json() {
    jq -nc --arg t "$1" --arg k "$2" --arg v "$3" --arg cwd "$T" '{tool_name:$t,cwd:$cwd,tool_input:{($k):$v}}'
}

mkdir -p "$T/src/lib"
printf 'line one\nline two\nline three\n' > "$T/src/app.sh"
printf 'alpha\nbeta\n' > "$T/src/other.sh"
printf 'x\ny\n' > "$T/src/lib/util.sh"

# Sections 2-7 of a valid investigation.md; section 1 varies per case.
INV_REST=$'## 2. Existing implementation patterns\nb\n## 3. Impact surface\nb\n## 4. Prior similar implementations\nb\n## 5. Side effects and risks\nb\n## 6. Constraints\nb\n## 7. Verification strategy\nb\n'
inv_with_related() {
    printf '## 1. Related files\n%s\n%s' "$1" "$INV_REST" > "$TASKS/investigation.md"
}

ADV4='vdgg_state_advance 4 planning'

# ---------------------------------------------------------------- 1. read gate
write_state investigating 3
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh` — entry point'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: unread Related file blocks Step 4"
assert_contains "$(cat "$T/hook.err")" "src/app.sh" "1: the refusal names the unread file"

# Bash cat is a read (the must-have case: not misjudged as unread).
assert_exit_code 0 "$(run_hook "$(bash_json 'cat src/app.sh')")" "1: cat itself passes"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV4")")" "1: file read with Bash cat counts as read"

# Read tool, sed -n, head, rg and grep all count; a directory entry is satisfied
# by a file read inside it.
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh:12` — entry
- src/other.sh: helper
- `src/lib/` — utilities'
run_hook "$(tool_json Read file_path "$T/src/app.sh")" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: partially read Related files still block"
run_hook "$(bash_json "sed -n '1,2p' src/other.sh | head -1")" >/dev/null
run_hook "$(bash_json 'rg -n "x y" src/lib/util.sh')" >/dev/null
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV4")")" "1: Read + sed -n + rg cover every Related file"

# head / grep / Grep tool.
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh`
- `src/other.sh`'
run_hook "$(bash_json 'head -n 5 src/app.sh')" >/dev/null
run_hook "$(tool_json Grep path "$T/src/other.sh")" >/dev/null
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV4")")" "1: head and the Grep tool count as reads"

# A grep pattern that happens to equal a path is not a read of that path.
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh`'
run_hook "$(bash_json 'grep -n src/app.sh src/other.sh')" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: a grep pattern is not a read"

# Quoting: a | or ; inside quotes does not split the command, and text in a
# here-document or an echo string is not a read.
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh`
- `src/other.sh`'
run_hook "$(bash_json "grep -nE 'line|two' src/app.sh")" >/dev/null
run_hook "$(bash_json 'echo "x; cat src/other.sh"')" >/dev/null
run_hook "$(bash_json $'cat > notes.md <<\'EOF\'\ncat src/other.sh\nEOF')" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: quoted text and here-doc bodies are not reads"
assert_contains "$(cat "$T/hook.err")" "src/other.sh" "1: only the file never read is reported"
run_hook "$(bash_json "sed -n '1p;3p' src/other.sh")" >/dev/null
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV4")")" "1: a quoted ; in a sed script still counts the file"

# Nothing listed, a listed file that does not exist, or a path out of the repo.
inv_with_related 'Everything relevant is described in prose only.'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: zero Related files blocks"
rm -f "$READ_LOG"
inv_with_related '- `src/missing.sh`'
run_hook "$(bash_json 'cat src/missing.sh')" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: a listed file that does not exist blocks"
OUTSIDE="$(dirname "$T")/vdgg-outside-$$.sh"
printf 'x\n' > "$OUTSIDE"
run_hook "$(bash_json "cat ../$(basename "$OUTSIDE")")" >/dev/null
inv_with_related "- \`../$(basename "$OUTSIDE")\`"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: a path outside the repository blocks"
assert_contains "$(cat "$T/hook.err")" "not a repository-relative path" "1: refused as outside the repository, not as missing"
rm -f "$OUTSIDE"

# Reads outside the investigating phase are not evidence.
rm -f "$READ_LOG"
write_state requirements 2
run_hook "$(bash_json 'cat src/app.sh')" >/dev/null
assert_file_not_exists "$READ_LOG" "1: reads before Step 3 are not recorded"
write_state investigating 3
inv_with_related '- `src/app.sh`'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "1: a read from Step 2 does not open Step 4"

# The read log is a sidecar: the agent cannot write it.
assert_exit_code 2 "$(run_hook "$(bash_json 'echo src/app.sh >> .claude/.vdgg-read-test-id')")" "1: forging the read log is blocked"

# ------------------------------------------------------------- 2. plan excerpts
ADV5='vdgg_state_advance 5 task-selected'
write_state planning 4
printf 'progress\n' > "$TASKS/progress.md"
write_todo() { printf '%s\n' "$1" > "$TASKS/todo.md"; }

GOOD_TASK='## T1: tweak app
### Location
`src/app.sh:2`
### Excerpt
```sh
line one
line two
```
### Intent
Rename the second line.'

rm -f "$TASKS/todo.md"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: missing todo.md blocks"

write_todo "$GOOD_TASK"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "2: verbatim excerpt with intent passes"

write_todo "${GOOD_TASK/line two/line 2}"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: excerpt that differs from the file blocks"
assert_contains "$(cat "$T/hook.err")" "T1" "2: the refusal names the task"

write_todo "${GOOD_TASK/line two/  line two}"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: indentation must match too"

write_todo '## T1: tweak app
### Location
`src/app.sh`
### Excerpt
```sh
line two
```
### Intent
x'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: a one-line excerpt is too thin"

write_todo "${GOOD_TASK%%### Intent*}"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: missing Intent blocks"

write_todo "${GOOD_TASK}
\`\`\`sh
line one
line TWO
\`\`\`"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: code in the Intent (the after-image) blocks"

write_todo '## T1: add helper
### Location
`src/new_helper.sh`
### Excerpt
新規
### Intent
Create the helper.'
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "2: 新規 for a file that does not exist passes"

write_todo '## T1: add helper
### Location
`src/app.sh`
### Excerpt
new
### Intent
Pretend it is new.'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: new for an existing file blocks"

write_todo '# Plan only prose'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: a plan with no task heading blocks"

# Two tasks: the second one is wrong, so the whole plan is refused.
write_todo "$GOOD_TASK

## T2: other
### Location
\`src/other.sh\`
### Excerpt
\`\`\`sh
alpha
gamma
\`\`\`
### Intent
x"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "2: every task is checked"

# vdgg_task_begin also leaves Step 4, so it is gated the same way.
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_task_begin "T1: x" src/app.sh')")" "2: vdgg_task_begin from planning is gated"
write_todo "$GOOD_TASK"
assert_exit_code 0 "$(run_hook "$(bash_json 'vdgg_task_begin "T1: x" src/app.sh')")" "2: vdgg_task_begin passes with a good plan"

# ------------------------------------------------------------ 3. patch first
ALLOW="$T/.claude/.vdgg-task-allowlist-test-id-0"
printf 'src/app.sh\n' > "$ALLOW"
CHAIN="$T/.claude/.vdgg-task-patchchain-test-id"
write_state implementing 6 "T1: tweak app" "$ALLOW"

assert_exit_code 2 "$(run_hook "$(tool_json Edit file_path "$T/src/app.sh")")" "3: direct Edit of an allowlisted file is blocked in implementing"
assert_exit_code 2 "$(run_hook "$(tool_json Write file_path "$T/src/app.sh")")" "3: direct Write is blocked in implementing"
assert_exit_code 2 "$(run_hook "$(tool_json NotebookEdit notebook_path "$T/src/app.sh")")" "3: NotebookEdit is blocked in implementing"
assert_exit_code 0 "$(run_hook "$(tool_json Write file_path "$TASKS/patch/T1.patch")")" "3: writing the patch file is allowed"

ADV7='vdgg_state_advance 7 testing'
rm -f "$CHAIN"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "3: 6 -> 7 without a patch chain blocks"
(
    . "$ROOT/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_write "$CHAIN" 0 "$T" "$ALLOW"
) || fail "3: chain fixture write failed"
assert_eq "applied=0" "$(head -1 "$CHAIN")" "3: fixture chain has nothing applied"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "3: 6 -> 7 with no applied patch blocks"
assert_contains "$(cat "$T/hook.err")" "no patch applied yet" "3: refused for the missing apply"
(
    . "$ROOT/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_write "$CHAIN" 1 "$T" "$ALLOW"
) || fail "3: chain fixture write failed"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV7")")" "3: 6 -> 7 with an intact chain passes"
printf 'sneaked\n' >> "$T/src/app.sh"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "3: an edit after the last apply blocks 6 -> 7"
assert_contains "$(cat "$T/hook.err")" "src/app.sh" "3: the refusal names the drifted file"
printf 'line one\nline two\nline three\n' > "$T/src/app.sh"

# Testing refuses direct edits too: a review fix goes through reflection and
# the next loop's patch.
write_state testing 7 "T1: tweak app" "$ALLOW"
assert_exit_code 2 "$(run_hook "$(tool_json Edit file_path "$T/src/app.sh")")" "3: direct edit in testing is refused too"

# Quoting the step or phase does not step around a gate.
write_state implementing 6 "T1: tweak app" "$ALLOW"
printf 'sneaked\n' >> "$T/src/app.sh"
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_state_advance "7" '"'"'testing'"'"'')")" "3: a quoted 6 -> 7 is gated like the plain one"
printf 'line one\nline two\nline three\n' > "$T/src/app.sh"
write_state investigating 3
rm -f "$READ_LOG"
inv_with_related '- `src/app.sh`'
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_state_advance "4" planning')")" "1: a quoted 3 -> 4 is gated like the plain one"
assert_exit_code 2 "$(run_hook "$(bash_json 'n=4; vdgg_state_advance $n planning')")" "1: a transition through a variable is refused"
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_state_advance 4 planning;true')")" "1: a trailing ; does not hide the transition from the gate"
assert_exit_code 0 "$(run_hook "$(bash_json 'grep -n vdgg_state_advance src/app.sh')")" "1: naming the helper as data is not a transition"

# ---------------------------------------------------- 4. plan reconciliation
write_todo "$GOOD_TASK"
write_state testing 7 "T1: tweak app" "$ALLOW"
printf 'passed=1\n' > "$T/.claude/.vdgg-task-gate-test-id-0"
VERIFY='vdgg_state_advance 7 verified'

printf '# progress\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.claude" test-id 0
assert_exit_code 2 "$(run_hook "$(bash_json "$VERIFY")")" "4: planned task without a reconciliation record blocks verified"

printf '# progress\n\n### Plan reconciliation: T1\n\n## Next\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.claude" test-id 0
assert_exit_code 2 "$(run_hook "$(bash_json "$VERIFY")")" "4: an empty reconciliation record blocks"

printf '# progress\n\n### Plan reconciliation: T10\nmatches\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.claude" test-id 0
assert_exit_code 2 "$(run_hook "$(bash_json "$VERIFY")")" "4: a record for another task (T10) does not count for T1"

printf '# progress\n\n### Plan reconciliation: T1\n- src/app.sh: matches the plan\n- src/extra.sh: not planned, needed for X\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.claude" test-id 0
assert_exit_code 0 "$(run_hook "$(bash_json "$VERIFY")")" "4: a reconciliation record (with discrepancies) passes"

# Tasks that are not in todo.md (followup TF tasks) need no record.
write_state testing 7 "TF1: followup" "$ALLOW"
printf '# progress\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.claude" test-id 0
assert_exit_code 0 "$(run_hook "$(bash_json "$VERIFY")")" "4: an unplanned followup task needs no record"

# ------------------------------------------ 3b. patch helpers in a real repo
R=$(mktemp -d)
(
    set -u
    cd "$R" || exit 1
    git init -q .
    git config user.email vdgg-test@example.com
    git config user.name vdgg-test
    mkdir -p src
    printf 'one\ntwo\nthree\n' > src/app.sh
    printf 'keep\n' > src/other.sh
    for n in 1 2 3 4; do printf 'f%s\n' "$n" > "src/m$n.sh"; done
    git add -A && git commit -qm init

    VDGG_CWD="$R"
    . "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
    vdgg_state_init >/dev/null 2>&1
    ID=$(vdgg_get_id)
    P="tasks/vdgg/$ID/patch"
    mkdir -p "$P"
    vdgg_state_advance 2 requirements >/dev/null 2>&1
    vdgg_state_advance 3 investigating >/dev/null 2>&1
    vdgg_state_advance 4 planning >/dev/null 2>&1
    vdgg_state_advance 5 task-selected >/dev/null 2>&1
    vdgg_task_begin "T1: tweak" src/app.sh >/dev/null 2>&1
    CHAIN=".claude/.vdgg-task-patchchain-$ID"
    assert_file_exists "$CHAIN" "3b: vdgg_task_begin starts the patch chain"
    assert_eq "applied=0" "$(head -1 "$CHAIN")" "3b: a new chain has nothing applied"

    printf -- '--- a/src/app.sh\n+++ b/src/app.sh\n@@ -1,3 +1,3 @@\n one\n-two\n+TWO\n three\n' > "$P/T1.patch"
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: vdgg_patch_apply refuses outside implementing"

    vdgg_state_advance 6 implementing >/dev/null 2>&1
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: a valid patch applies"
    assert_eq "TWO" "$(sed -n 2p src/app.sh)" "3b: the patch changed the file"
    assert_eq "applied=1" "$(head -1 "$CHAIN")" "3b: the chain counts the apply"
    . "$ROOT/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_check "$CHAIN" "$(grep '^task_allowlist_file=' ".claude/.vdgg-state-$ID" | cut -d= -f2-)" "$R" >/dev/null
    assert_exit_code 0 "$?" "3b: the chain is intact after the apply"

    # Stale context: the same patch no longer applies (git apply --check).
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: a patch whose context no longer matches is refused"
    assert_eq "TWO" "$(sed -n 2p src/app.sh)" "3b: a refused patch leaves the file alone"

    # Off the allowlist.
    printf -- '--- a/src/other.sh\n+++ b/src/other.sh\n@@ -1 +1 @@\n-keep\n+changed\n' > "$P/T1-off.patch"
    vdgg_patch_apply "$P/T1-off.patch" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: a patch touching a non-allowlisted file is refused"
    assert_eq "keep" "$(cat src/other.sh)" "3b: the non-allowlisted file is untouched"

    # Outside the patch directory.
    # A patch that would apply (allowlisted file, current context) is still
    # refused when it does not live under tasks/vdgg/<id>/patch/.
    printf -- '--- a/src/app.sh\n+++ b/src/app.sh\n@@ -1,3 +1,3 @@\n-one\n+ONE\n TWO\n three\n' > "$T/outside.patch"
    vdgg_patch_apply "$T/outside.patch" >/dev/null 2>"$T/err3b"
    assert_exit_code 1 "$?" "3b: a patch outside tasks/vdgg/<id>/patch/ is refused"
    assert_contains "$(cat "$T/err3b")" "under tasks/vdgg/" "3b: refused for its location"
    assert_eq "one" "$(sed -n 1p src/app.sh)" "3b: the outside patch changed nothing"

    # A direct edit after the last apply is drift: apply refuses, and so would 6 -> 7.
    printf 'sneaked\n' >> src/app.sh
    printf -- '--- a/src/app.sh\n+++ b/src/app.sh\n@@ -1,3 +1,3 @@\n-one\n+ONE\n TWO\n three\n' > "$P/T1-2.patch"
    vdgg_patch_apply "$P/T1-2.patch" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: apply refuses when the tree drifted outside a patch"

    # Rollback restores the baseline and restarts the chain.
    vdgg_task_rollback >/dev/null 2>&1
    assert_eq "two" "$(sed -n 2p src/app.sh)" "3b: rollback restores the baseline"
    assert_eq "applied=0" "$(head -1 "$CHAIN")" "3b: rollback restarts the chain"
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: the patch applies again after rollback"

    # vdgg_plan_diff lists planned vs changed files and the diff.
    mkdir -p "tasks/vdgg/$ID"
    printf '## T1: tweak\n### Location\n`src/app.sh:2`\n### Excerpt\n```\none\ntwo\n```\n### Intent\nx\n### Location\n`src/planned.sh`\n### Excerpt\n新規\n' > "tasks/vdgg/$ID/todo.md"
    OUT=$(vdgg_plan_diff 2>/dev/null)
    assert_exit_code 0 "$?" "4b: vdgg_plan_diff succeeds"
    assert_file_exists "$OUT" "4b: vdgg_plan_diff writes the report"
    assert_contains "$(cat "$OUT")" '- planned, changed: `src/app.sh`' "4b: planned and changed file"
    assert_contains "$(cat "$OUT")" '- planned, NOT changed: `src/planned.sh`' "4b: planned but not made"
    assert_contains "$(cat "$OUT")" '+TWO' "4b: the report carries the diff"
    RP=$(cd -P "$R" && pwd -P)
    case "$(cat "$OUT")" in
        *"$R"*|*"$RP"*) fail "4b: the report leaks absolute paths" ;;
    esac

    # The user-facing pre-checks mirror the gates.
    printf '## 1. Related files\n- `src/app.sh`\n' > "tasks/vdgg/$ID/investigation.md"
    vdgg_check_investigation >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: vdgg_check_investigation reports an unread file"
    printf 'src/app.sh\n' >> ".claude/.vdgg-read-$ID"
    vdgg_check_investigation >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: vdgg_check_investigation passes once it was read"
    vdgg_check_plan >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: vdgg_check_plan reports the stale excerpt (the patch changed line 2)"
    printf '## T1: tweak\n### Location\n`src/app.sh`\n### Excerpt\n```\none\nTWO\n```\n### Intent\nx\n' > "tasks/vdgg/$ID/todo.md"
    vdgg_check_plan >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: vdgg_check_plan passes on a current excerpt"

    # An edit made outside a patch during testing is not absorbed by the next
    # loop: the chain still reports it until it is rolled back.
    vdgg_state_advance 7 testing >/dev/null 2>&1
    printf 'review fix\n' >> src/app.sh
    vdgg_state_advance 6 reflection >/dev/null 2>&1
    vdgg_state_loop 6 implementing >/dev/null 2>&1
    _vdgg_ev_chain_check "$CHAIN" "$(grep '^task_allowlist_file=' ".claude/.vdgg-state-$ID" | cut -d= -f2-)" "$R" >/dev/null
    assert_exit_code 1 "$?" "3b: a testing-phase edit outside a patch still blocks the next 6 -> 7"
    vdgg_task_rollback >/dev/null 2>&1
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: after rollback the fix goes in as a patch"

    # Each step has its own phases, and verified is entered only from testing.
    vdgg_state_advance 6 testing >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: implementing cannot jump to testing within step 6"
    vdgg_state_advance 7 verified >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: implementing cannot jump straight to verified"

    # Too many files: split the task. Codemod count must match the dry run.
    vdgg_state_advance 7 testing >/dev/null 2>&1
    vdgg_state_advance 7 verified >/dev/null 2>&1
    vdgg_state_advance 8 progress >/dev/null 2>&1
    vdgg_state_advance 5 task-selected >/dev/null 2>&1
    vdgg_task_begin "T2: bulk" src/m1.sh src/m2.sh src/m3.sh src/m4.sh >/dev/null 2>&1
    vdgg_state_advance 6 implementing >/dev/null 2>&1
    {
        for n in 1 2 3 4; do
            printf -- '--- a/src/m%s.sh\n+++ b/src/m%s.sh\n@@ -1 +1 @@\n-f%s\n+g%s\n' "$n" "$n" "$n" "$n"
        done
    } > "$P/T2.patch"
    vdgg_patch_apply "$P/T2.patch" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: a patch touching 4 files is refused (split the task)"
    assert_eq "f1" "$(cat src/m1.sh)" "3b: the refused 4-file patch changed nothing"

    vdgg_codemod_apply 0 true >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: a codemod expecting no change is refused"
    vdgg_codemod_apply 3 perl -pi -e 's/^f/g/' src/m1.sh src/m2.sh >/dev/null 2>"$T/err3b"
    assert_exit_code 1 "$?" "3b: a codemod whose count differs from the dry run is refused"
    assert_contains "$(cat "$T/err3b")" "the dry run predicted 3" "3b: refused for the count"
    vdgg_task_rollback >/dev/null 2>&1
    assert_eq "f1" "$(cat src/m1.sh)" "3b: rollback undoes the refused codemod"
    vdgg_codemod_apply 4 sed -i.bak 's/^f/g/' src/m1.sh src/m2.sh src/m3.sh src/m4.sh >/dev/null 2>&1
    RC=$?
    rm -f src/m*.sh.bak
    assert_exit_code 1 "$RC" "3b: a codemod leaving files off the allowlist (sed backups) is refused"
    vdgg_task_rollback >/dev/null 2>&1
    vdgg_codemod_apply 4 perl -pi -e 's/^f/g/' src/m1.sh src/m2.sh src/m3.sh src/m4.sh >/dev/null 2>&1
    assert_exit_code 0 "$?" "3b: a codemod matching the dry-run count passes"
    assert_eq "applied=1" "$(head -1 "$CHAIN")" "3b: the codemod counts as an apply"

    # A leading - never reaches find: such an allowlist entry is refused.
    vdgg_state_advance 7 testing >/dev/null 2>&1
    vdgg_state_advance 7 verified >/dev/null 2>&1
    vdgg_state_advance 8 progress >/dev/null 2>&1
    vdgg_state_advance 5 task-selected >/dev/null 2>&1
    vdgg_task_begin "T3: x" -delete >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: an allowlist entry starting with - is refused"
    vdgg_task_begin "T3: x" ".claude/.vdgg-state-$ID" >/dev/null 2>&1
    assert_exit_code 1 "$?" "3b: a sidecar cannot be allowlisted"
) || fail "3b: patch helper checks aborted"
rm -rf "$R"

# Step/phase pairing: a same-step phase jump cannot walk past the phase gates.
R2=$(mktemp -d)
(
    cd "$R2" || exit 1
    git init -q . && git config user.email t@e && git config user.name t
    VDGG_CWD="$R2"
    . "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"
    vdgg_state_init >/dev/null 2>&1
    vdgg_state_advance 2 requirements >/dev/null 2>&1
    vdgg_state_advance 3 investigating >/dev/null 2>&1
    vdgg_state_advance 3 planning >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: investigating cannot become planning within step 3"
    vdgg_state_write 4 task-selected 0 >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: step 4 has no task-selected phase"
    vdgg_state_advance 4 planning >/dev/null 2>&1
    assert_exit_code 0 "$?" "pairing: the gated 3 -> 4 planning still works"
    vdgg_state_advance 5 task-selected >/dev/null 2>&1
    vdgg_task_begin "T1: x" ".claude/" >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: a non-canonical sidecar dir (.claude/) cannot be allowlisted"
    vdgg_task_begin "T1: x" "src//a.sh" >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: a non-canonical path (src//a.sh) cannot be allowlisted"
    vdgg_state_advance 6 implementing >/dev/null 2>&1
    vdgg_state_advance 6 reflection >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: implementing cannot detour through reflection"
    vdgg_state_write 7 testing 0 >/dev/null 2>&1
    assert_exit_code 0 "$?" "pairing: implementing -> testing is the only way to step 7"
    vdgg_state_advance 6 reflection >/dev/null 2>&1
    assert_exit_code 0 "$?" "pairing: testing -> reflection still works"
    vdgg_state_advance 7 testing >/dev/null 2>&1
    assert_exit_code 1 "$?" "pairing: reflection cannot go straight back to testing"
) || fail "pairing checks aborted"
rm -rf "$R2"

# A hook without its evidence library refuses instead of opening the gates.
H=$(mktemp -d)
cp "$PRETOOL" "$H/vdgg-hook-pretool.sh"
write_state investigating 3
set +e
printf '%s' "$(bash_json 'cat src/app.sh')" | bash "$H/vdgg-hook-pretool.sh" >/dev/null 2>&1
RC=$?
assert_exit_code 2 "$RC" "a hook missing vdgg-evidence.sh fails closed"
rm -rf "$H"

# ---------------------------------------------- 5. plan review seat (4R)
. "$ROOT/tests/lib/exec-fixtures.sh"
export VDGG_CONFIG_DIR="$T/user-config"
vdgg_install_exec_fixtures "$T/bin" "$VDGG_CONFIG_DIR"
mkdir -p "$VDGG_CONFIG_DIR/formations"
printf '4: primary\n4R: okexec\n' > "$VDGG_CONFIG_DIR/formations/with4r.conf"
printf '*: okexec\n' > "$VDGG_CONFIG_DIR/formations/wild.conf"
PLAN_OK_TODO="$(cat "$TASKS/todo.md" 2>/dev/null)"
write_state planning 4
sed -i.bak 's/^formation=.*//' "$T/.claude/.vdgg-state-test-id" && rm -f "$T/.claude/.vdgg-state-test-id.bak"
printf 'formation=with4r\n' >> "$T/.claude/.vdgg-state-test-id"
printf 'progress\n' > "$TASKS/progress.md"
rm -f "$TASKS/plan-review.md"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "5: a Formation with 4R blocks Step 5 until plan-review.md exists"
assert_contains "$(cat "$T/hook.err")" "4R" "5: the refusal names seat 4R"
printf '## Findings\n- none\n' > "$TASKS/plan-review.md"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "5: the plan review opens Step 5"
rm -f "$TASKS/plan-review.md"
sed -i.bak 's/^formation=.*/formation=wild/' "$T/.claude/.vdgg-state-test-id" && rm -f "$T/.claude/.vdgg-state-test-id.bak"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "5: the * wildcard does not assign 4R"
unset VDGG_CONFIG_DIR

echo "evidence gates: all checks passed"
