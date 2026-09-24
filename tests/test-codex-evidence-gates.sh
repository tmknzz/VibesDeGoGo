#!/bin/bash
# test-codex-evidence-gates.sh — Codex edition of test-evidence-gates.sh.
# Codex exposes no Read tool to the hook, so read evidence comes from Bash.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/sentinel-fixtures.sh"

PRETOOL="$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
TASKS="$T/tasks/vdgg/test-id"
READ_LOG="$T/.codex/.vdgg-read-test-id"

write_state() {
    local phase="$1" step="$2" task="${3:-T}" allowlist="${4:-}"
    mkdir -p "$T/.codex" "$TASKS"
    printf 'test-id\n' > "$T/.codex/.vdgg-active"
    cat > "$T/.codex/.vdgg-state-test-id" <<EOF
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

mkdir -p "$T/functions"
printf 'const a = 1;\nconst b = 2;\n' > "$T/functions/index.js"
printf 'x\ny\n' > "$T/functions/util.js"

INV_REST=$'## 2. Existing implementation patterns\nb\n## 3. Impact surface\nb\n## 4. Prior similar implementations\nb\n## 5. Side effects and risks\nb\n## 6. Constraints\nb\n## 7. Verification strategy\nb\n'
inv_with_related() {
    printf '## 1. Related files\n%s\n%s' "$1" "$INV_REST" > "$TASKS/investigation.md"
}
ADV4='vdgg_state_advance 4 planning'

# ---------------------------------------------------------------- 1. read gate
write_state investigating 3
rm -f "$READ_LOG"
inv_with_related '- `functions/index.js`
- `functions/util.js`'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "codex 1: unread Related files block Step 4"
run_hook "$(bash_json 'cat functions/index.js')" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "codex 1: one unread file still blocks"
assert_contains "$(cat "$T/hook.err")" "functions/util.js" "codex 1: the refusal names the unread file"
run_hook "$(bash_json "sed -n '1,5p' functions/util.js")" >/dev/null
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV4")")" "codex 1: files read with cat and sed -n count as read"

# Reads before Step 3 are not evidence; a grep pattern is not a read; a
# quoted transition is gated like a plain one.
rm -f "$READ_LOG"
write_state requirements 2
run_hook "$(bash_json 'cat functions/index.js')" >/dev/null
assert_file_not_exists "$READ_LOG" "codex 1: reads before Step 3 are not recorded"
write_state investigating 3
inv_with_related '- `functions/index.js`'
run_hook "$(bash_json 'grep -n functions/index.js functions/util.js')" >/dev/null
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_state_advance "4" planning')")" "codex 1: a grep pattern is not a read, and quoting does not skip the gate"

inv_with_related 'prose only'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "codex 1: zero Related files blocks"
inv_with_related '- `functions/missing.js`'
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV4")")" "codex 1: a missing file blocks"
assert_exit_code 2 "$(run_hook "$(bash_json 'echo functions/util.js >> .codex/.vdgg-read-test-id')")" "codex 1: forging the read log is blocked"

# ------------------------------------------------------------- 2. plan excerpts
ADV5='vdgg_state_advance 5 task-selected'
write_state planning 4
GOOD_TASK='## T1: tweak index
### Location
`functions/index.js:1`
### Excerpt
```js
const a = 1;
const b = 2;
```
### Intent
Change b.'
printf '%s\n' "$GOOD_TASK" > "$TASKS/todo.md"
printf 'progress\n' > "$TASKS/progress.md"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "codex 2: verbatim excerpt passes"
printf '%s\n' "${GOOD_TASK/const b = 2;/const b = 3;}" > "$TASKS/todo.md"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "codex 2: excerpt that differs from the file blocks"
assert_exit_code 2 "$(run_hook "$(bash_json 'vdgg_task_begin "T1: x" functions/index.js')")" "codex 2: vdgg_task_begin from planning is gated"
printf '%s\n' "$GOOD_TASK" > "$TASKS/todo.md"
assert_exit_code 0 "$(run_hook "$(bash_json 'vdgg_task_begin "T1: x" functions/index.js')")" "codex 2: vdgg_task_begin passes with a good plan"
printf '## T1: add\n### Location\n`functions/new.js`\n### Excerpt\n新規\n### Intent\nCreate it.\n' > "$TASKS/todo.md"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "codex 2: 新規 for a new file passes"
printf '## T1: x\n### Location\n`functions/index.js`\n### Excerpt\n```js\nconst a = 1;\nconst b = 2;\n```\n### Intent\nx\n```js\nconst b = 3;\n```\n' > "$TASKS/todo.md"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "codex 2: code in the Intent blocks"
printf '%s\n' "$GOOD_TASK" > "$TASKS/todo.md"

# ------------------------------------------------------------ 3. patch first
ALLOW="$T/.codex/.vdgg-task-allowlist-test-id-0"
printf 'functions/index.js\n' > "$ALLOW"
CHAIN="$T/.codex/.vdgg-task-patchchain-test-id"
write_state implementing 6 "T1: tweak index" "$ALLOW"
assert_exit_code 2 "$(run_hook "$(tool_json Edit file_path "$T/functions/index.js")")" "codex 3: direct Edit is blocked in implementing"
assert_exit_code 2 "$(run_hook "$(jq -nc --arg cwd "$T" '{tool_name:"apply_patch",cwd:$cwd,tool_input:{command:"*** Begin Patch\n*** Update File: functions/index.js\n@@\n-const b = 2;\n+const b = 3;\n*** End Patch"}}')")" "codex 3: apply_patch on an implementation file is blocked in implementing"
assert_exit_code 0 "$(run_hook "$(jq -nc --arg cwd "$T" '{tool_name:"apply_patch",cwd:$cwd,tool_input:{command:"*** Begin Patch\n*** Add File: tasks/vdgg/test-id/patch/T1.patch\n+x\n*** End Patch"}}')")" "codex 3: writing the patch file is allowed"

ADV7='vdgg_state_advance 7 testing'
rm -f "$CHAIN"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "codex 3: 6 -> 7 without a patch chain blocks"
(
    . "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_write "$CHAIN" 0 "$T" "$ALLOW"
) || fail "codex 3: chain fixture write failed"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "codex 3: 6 -> 7 with no applied patch blocks"
assert_contains "$(cat "$T/hook.err")" "no patch applied yet" "codex 3: refused for the missing apply"
(
    . "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_write "$CHAIN" 1 "$T" "$ALLOW"
) || fail "codex 3: chain fixture write failed"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV7")")" "codex 3: 6 -> 7 with an intact chain passes"
printf '// sneaked\n' >> "$T/functions/index.js"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV7")")" "codex 3: an edit after the last apply blocks 6 -> 7"
printf 'const a = 1;\nconst b = 2;\n' > "$T/functions/index.js"

# ---------------------------------------------------- 4. plan reconciliation
write_state testing 7 "T1: tweak index" "$ALLOW"
printf 'passed=1\n' > "$T/.codex/.vdgg-task-gate-test-id-0"
VERIFY='vdgg_state_advance 7 verified'
printf '# progress\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.codex" test-id 0
assert_exit_code 2 "$(run_hook "$(bash_json "$VERIFY")")" "codex 4: planned task without a reconciliation record blocks verified"
printf '# progress\n\n## Plan reconciliation: T1\nmatches the plan\n' > "$TASKS/progress.md"
write_review_sentinel "$T/.codex" test-id 0
assert_exit_code 0 "$(run_hook "$(bash_json "$VERIFY")")" "codex 4: a reconciliation record passes"
printf '# progress\n' > "$TASKS/progress.md"
write_state testing 7 "TF1: followup" "$ALLOW"
write_review_sentinel "$T/.codex" test-id 0
assert_exit_code 0 "$(run_hook "$(bash_json "$VERIFY")")" "codex 4: an unplanned followup task needs no record"

# ------------------------------- 3b. Codex state helpers in a real repository
R=$(mktemp -d)
(
    cd "$R" || exit 1
    git init -q . && git config user.email t@e && git config user.name t
    mkdir -p functions
    printf 'one\ntwo\nthree\n' > functions/index.js
    git add -A && git commit -qm init
    export VDGG_CWD="$R"
    . "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-state.sh"
    set +e
    vdgg_state_init >/dev/null 2>&1
    ID=$(vdgg_get_id)
    P="tasks/vdgg/$ID/patch"
    mkdir -p "$P"
    vdgg_state_advance 2 requirements >/dev/null 2>&1
    vdgg_state_advance 3 investigating >/dev/null 2>&1
    vdgg_state_advance 3 planning >/dev/null 2>&1
    assert_exit_code 1 "$?" "codex 3b: investigating cannot become planning within step 3"
    vdgg_state_advance 4 planning >/dev/null 2>&1
    vdgg_state_advance 5 task-selected >/dev/null 2>&1
    vdgg_task_begin "T1: tweak" functions/index.js >/dev/null 2>&1
    CHAIN=".codex/.vdgg-task-patchchain-$ID"
    assert_file_exists "$CHAIN" "codex 3b: vdgg_task_begin starts the patch chain"
    vdgg_state_advance 6 implementing >/dev/null 2>&1
    printf -- '--- a/functions/index.js\n+++ b/functions/index.js\n@@ -1,3 +1,3 @@\n one\n-two\n+TWO\n three\n' > "$P/T1.patch"
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    assert_exit_code 0 "$?" "codex 3b: a valid patch applies"
    assert_eq "applied=1" "$(head -1 "$CHAIN")" "codex 3b: the chain counts the apply"
    vdgg_state_advance 7 verified >/dev/null 2>&1
    assert_exit_code 1 "$?" "codex 3b: implementing cannot jump straight to verified"
    vdgg_task_rollback >/dev/null 2>&1
    assert_eq "two" "$(sed -n 2p functions/index.js)" "codex 3b: rollback restores the baseline"
    assert_eq "applied=0" "$(head -1 "$CHAIN")" "codex 3b: rollback restarts the chain"
    vdgg_patch_apply "$P/T1.patch" >/dev/null 2>&1
    vdgg_state_advance 7 testing >/dev/null 2>&1
    printf 'review fix\n' >> functions/index.js
    vdgg_state_advance 6 reflection >/dev/null 2>&1
    vdgg_state_loop 6 implementing >/dev/null 2>&1
    . "$ROOT/.agents/skills/vibesdegogo/scripts/vdgg-evidence.sh"
    _vdgg_ev_chain_check "$CHAIN" "$(grep '^task_allowlist_file=' ".codex/.vdgg-state-$ID" | cut -d= -f2-)" "$R" >/dev/null
    assert_exit_code 1 "$?" "codex 3b: a testing-phase edit outside a patch still blocks the next 6 -> 7"
    vdgg_task_rollback >/dev/null 2>&1
    vdgg_codemod_apply 1 perl -pi -e 's/two/TWO/' functions/index.js >/dev/null 2>&1
    assert_exit_code 0 "$?" "codex 3b: a codemod matching the dry-run count passes"
    printf '## T1: tweak\n### Location\n`functions/index.js`\n' > "tasks/vdgg/$ID/todo.md"
    OUT=$(vdgg_plan_diff 2>/dev/null)
    assert_contains "$(cat "$OUT")" '- planned, changed: `functions/index.js`' "codex 3b: vdgg_plan_diff reports the planned change"
    vdgg_state_clear >/dev/null 2>&1
    assert_file_not_exists "$CHAIN" "codex 3b: vdgg_state_clear removes the patch chain"
) || fail "codex 3b: state helper checks aborted"
rm -rf "$R"

# ---------------------------------------------- 5. plan review seat (4R)
. "$ROOT/tests/lib/exec-fixtures.sh"
export VDGG_CONFIG_DIR="$T/user-config"
vdgg_install_exec_fixtures "$T/bin" "$VDGG_CONFIG_DIR"
mkdir -p "$VDGG_CONFIG_DIR/formations"
printf '4: primary\n4R: okexec\n' > "$VDGG_CONFIG_DIR/formations/with4r.conf"
printf '*: okexec\n' > "$VDGG_CONFIG_DIR/formations/wild.conf"
PLAN_OK_TODO="$(cat "$TASKS/todo.md" 2>/dev/null)"
write_state planning 4
sed -i.bak 's/^formation=.*//' "$T/.codex/.vdgg-state-test-id" && rm -f "$T/.codex/.vdgg-state-test-id.bak"
printf 'formation=with4r\n' >> "$T/.codex/.vdgg-state-test-id"
printf 'progress\n' > "$TASKS/progress.md"
rm -f "$TASKS/plan-review.md"
assert_exit_code 2 "$(run_hook "$(bash_json "$ADV5")")" "codex 5: a Formation with 4R blocks Step 5 until plan-review.md exists"
assert_contains "$(cat "$T/hook.err")" "4R" "codex 5: the refusal names seat 4R"
printf '## Findings\n- none\n' > "$TASKS/plan-review.md"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "codex 5: the plan review opens Step 5"
rm -f "$TASKS/plan-review.md"
sed -i.bak 's/^formation=.*/formation=wild/' "$T/.codex/.vdgg-state-test-id" && rm -f "$T/.codex/.vdgg-state-test-id.bak"
assert_exit_code 0 "$(run_hook "$(bash_json "$ADV5")")" "codex 5: the * wildcard does not assign 4R"
unset VDGG_CONFIG_DIR

echo "codex evidence gates: all checks passed"
