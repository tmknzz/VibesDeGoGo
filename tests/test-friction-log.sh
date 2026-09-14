#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

PRETOOL="$ROOT/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
STOPHOOK="$ROOT/skills/vibesdegogo/scripts/vdgg-hook-stop.sh"
STATE_SH="$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"

TMPDIR_VDGG=$(mktemp -d)
UNARMED=$(mktemp -d)
LEAK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG" "$UNARMED" "$LEAK"' EXIT

LOG="$TMPDIR_VDGG/.claude/.vdgg-friction-test-id"

write_state() {
    local dir="$1" phase="$2" step="$3" loop="${4:-0}"
    mkdir -p "$dir/.claude" "$dir/tasks/vdgg/test-id"
    echo "test-id" > "$dir/.claude/.vdgg-active"
    cat > "$dir/.claude/.vdgg-state-test-id" <<EOF
step=${step}
phase=${phase}
loop_count=${loop}
current_task=T
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

run_pretool() {
    printf '%s' "$1" | bash "$PRETOOL" >/tmp/vdgg-test-friction.out 2>/tmp/vdgg-test-friction.err
    echo "$?"
}

# Lines in the log that start with the given event word; 0 before the log exists.
count() {
    local n
    n=$(grep -c "^$1 " "$LOG" 2>/dev/null)
    echo "${n:-0}"
}

# The source line a deny line's gate points at. bash 5 resets LINENO inside an
# EXIT trap, so this is the check that fails when the gate is taken from there.
gate_source() {
    local gate
    gate=$(printf '%s' "$1" | sed -n 's/.*gate=\([0-9][0-9]*\)$/\1/p')
    [ -n "$gate" ] && sed -n "${gate}p" "$PRETOOL"
}

# --- gate= stays meaningful only while no reachable function exits ---
# DEBUG traps are not inherited by functions, so an `exit` inside one makes
# gate= name the line before the call. `set -T` does not fix this: under
# functrace the trap fires for the EXIT handler's own body and overwrites the
# captured line (checked on bash 3.2 and 5.3). gate_source only reaches 2 of
# the 30-odd exit sites, so this scan is what covers the rest.
#
# The three exempt names all run before the trap arms; TRAP_LINE pins that.
# Calling one from a non-exempt function counts as exiting, since that is
# what they do -- depth does not matter, because each function is judged on
# its own body. What escapes is a name or command assembled at run time
# (f="${f}_deny"; $f), and anything after a column-0 } inside a body (an
# embedded awk block closed at column 0) -- defs/closes catches that unless
# another definition rebalances the count.
# Unreadable definition forms are reported, not skipped.
EXEMPT='_vdgg_entry_deny|_vdgg_entry_gate|_vdgg_unarmed_exit'
FUNC_SCAN='
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*function[[:space:]]/ || /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/ || /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*$/ { print NR " unreadable function form"; next }
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/ { infunc = 1; fname = $0; sub(/[[:space:]]*\(\).*$/, "", fname); defs++ }
    /^\}/ { closes++; infunc = 0; next }
    infunc && fname !~ "^(" exempt ")$" && /(^|[^A-Za-z0-9_])exit([^A-Za-z0-9_]|$)/ { print NR " " fname; next }
    infunc && fname !~ "^(" exempt ")$" && $0 ~ "(^|[^A-Za-z0-9_])(" exempt ")([^A-Za-z0-9_]|$)" { print NR " " fname " (calls an exiting helper)" }
    END { if (defs != closes) print "a column-0 } does not close a function: " defs " defs, " closes " closes" }'
FUNC_EXITS=$(awk -v exempt="$EXEMPT" "$FUNC_SCAN" "$PRETOOL")
# Control: assert_eq "" cannot tell "no violations" from "the scan never ran",
# and a portability gap (CI runs mawk, this runs BWK awk) degrades to zero
# matches rather than an error. Run the same program over a known violator.
assert_eq $'2 f\n5 g (calls an exiting helper)' "$(printf 'f() {\n    exit 2\n}\ng() {\n    _vdgg_entry_deny\n}\n' | awk -v exempt="$EXEMPT" "$FUNC_SCAN")" "control: both the exit rule and the exempt-call rule still fire"
# No closing brace here on purpose: defs and closes both stay unset, so the
# END rule cannot drown the one line this control is checking.
assert_eq "1 unreadable function form" "$(printf 'function h {\n' | awk -v exempt="$EXEMPT" "$FUNC_SCAN")" "control: the unreadable-form rule still fires"
assert_eq "" "$FUNC_EXITS" "the hook's exit sites are all readable and none is inside a function reachable under the DEBUG trap"

# The exemption above is only sound while those three run before the trap
# arms. A call below the trap line breaks it, and so does a trap string at
# any line -- the hook itself registers _vdgg_friction_on_exit that way one
# line above the DEBUG trap, so position alone does not mean "runs early".
TRAP_LINE=$(grep -n '^trap .* DEBUG$' "$PRETOOL" | cut -d: -f1)
assert_eq "1" "$(grep -c '^trap .* DEBUG$' "$PRETOOL")" "the DEBUG trap is armed at exactly one line"
LATE_SCAN='
    /^[[:space:]]*#/ { next }
    (NR > t || /^[[:space:]]*trap[[:space:]]/) && $0 ~ "(^|[^A-Za-z0-9_])(" ex ")([^A-Za-z0-9_]|$)" { print NR }'
LATE_CALLS=$(awk -v t="$TRAP_LINE" -v ex="$EXEMPT" "$LATE_SCAN" "$PRETOOL")
assert_eq $'1\n3' "$(printf "trap '_vdgg_entry_deny' EXIT\nnothing here\n_vdgg_entry_gate x\n" | awk -v t=2 -v ex="$EXEMPT" "$LATE_SCAN")" "control: both the trap-string branch and the NR>t branch still fire"
assert_eq "" "$LATE_CALLS" "the exempted functions run only before the DEBUG trap arms: not below it, and never from a trap string"

# The hook sources vdgg-state.sh under the armed trap -- a top-level `exit`
# there takes the hook down with it -- and calls _vdgg_review_gate_ready
# without a subshell, so an `exit` anywhere in that
# file -- top level or inside any function -- breaks gate= the same way.
# Matches `exit` only in command position, so the word inside a message
# string ("failed: exit $status") and flags like --exit-code stay quiet.
# awk, not grep: the two scans above are awk and this needs the same
# comment-skip rule.
STATE_SCAN='
    /^[[:space:]]*#/ { next }
    /(^|[;&|(){}]|[[:space:]](then|else|do)[[:space:]])[[:space:]]*exit([[:space:]]|;|$)/ { print NR " " $0 }'
STATE_EXITS=$(awk "$STATE_SCAN" "$STATE_SH")
assert_eq $'1     exit 1\n2 [ -n "$x" ] || exit 1\n3 if [ "$x" = y ]; then exit 2; fi' "$(printf '    exit 1\n[ -n "$x" ] || exit 1\nif [ "$x" = y ]; then exit 2; fi\n' | awk "$STATE_SCAN")" "control: the line-start, operator and then-branch alternatives all still fire"
assert_eq "" "$STATE_EXITS" "vdgg-state.sh never exits: the hook sources it under the armed trap and calls into it without a subshell"

# --- pretool: one refusal appends one deny line that names its gate ---
write_state "$TMPDIR_VDGG" implementing 6 0
run_pretool '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"swift test"}}' >/dev/null
assert_eq "1" "$(count deny)" "one refusal appends one deny line"
LINE=$(grep '^deny ' "$LOG" | head -1)
assert_contains "$LINE" "phase=implementing" "deny line records the phase"
assert_contains "$LINE" "tool=Bash" "deny line records the tool"
assert_contains "$(gate_source "$LINE")" "exit 2" "gate points at the exit that refused a test command"

# --- pretool: an allowed call writes nothing ---
run_pretool '{"tool_name":"Read","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/x"}}' >/dev/null
assert_eq "1" "$(count deny)" "an allowed call leaves the log unchanged"

# --- entry gate: refusals before a session is armed are not friction ---
mkdir -p "$UNARMED/.claude"
printf 'VDGG_REQUIRED=on\n' > "$UNARMED/.vdgg-target"
STATUS=$(run_pretool '{"tool_name":"Edit","cwd":"'"$UNARMED"'","tool_input":{"file_path":"'"$UNARMED"'/a.txt"}}')
assert_exit_code 2 "$STATUS" "entry gate still refuses an unarmed edit"
assert_eq "0" "$(find "$UNARMED/.claude" -name '.vdgg-friction-*' | wc -l | tr -d ' ')" "an unarmed refusal creates no log"

# --- a log that cannot be written never leaks into the refusal message ---
write_state "$LEAK" implementing 6 0
mkdir -p "$LEAK/.claude/.vdgg-friction-test-id"
STATUS=$(run_pretool '{"tool_name":"Bash","cwd":"'"$LEAK"'","tool_input":{"command":"swift test"}}')
assert_exit_code 2 "$STATUS" "the refusal stands when the log cannot be written"
case "$(cat /tmp/vdgg-test-friction.err)" in
    *friction*) fail "an unwritable log leaked into the refusal message" ;;
esac

# --- stop hook: a refused silent stop appends one stop line ---
TRANSCRIPT="$TMPDIR_VDGG/transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"continue"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"done for now"}]}}
EOF
printf '%s' '{"cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$TRANSCRIPT"'"}' | bash "$STOPHOOK" >/dev/null 2>&1
assert_eq "1" "$(count stop)" "a refused stop appends one stop line"

cd "$TMPDIR_VDGG" || exit 1
VDGG_CWD="$TMPDIR_VDGG"
source "$STATE_SH"

# --- retries: vdgg_state_loop appends one loop line ---
write_state "$TMPDIR_VDGG" testing 7 0
vdgg_state_loop 6 implementing >/dev/null 2>&1
assert_eq "1" "$(count loop)" "a retry appends one loop line"

# --- a new task marks its start, and reflection shows only that task ---
git init -q "$TMPDIR_VDGG"
write_state "$TMPDIR_VDGG" task-selected 5 0
vdgg_task_begin "T2: second task" README.md >/dev/null 2>&1
assert_eq "1" "$(count task)" "vdgg_task_begin marks the task boundary"
write_state "$TMPDIR_VDGG" implementing 6 0
run_pretool '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.claude/.vdgg-state-test-id"}}' >/dev/null
EDIT_LINE=$(grep '^deny .*tool=Edit' "$LOG" | tail -1)
assert_contains "$(gate_source "$EDIT_LINE")" "exit 2" "gate points at the exit that refused a sidecar edit"
# A third task, so two markers exist and the display must reset on the LAST
# one. With a single marker, resetting on the first is indistinguishable.
write_state "$TMPDIR_VDGG" task-selected 5 0
vdgg_task_begin "T3: third task" README.md >/dev/null 2>&1
write_state "$TMPDIR_VDGG" implementing 6 0
# Two refusals after that marker: with only one, an implementation printing
# just the last line would be indistinguishable from one honouring the
# boundary.
run_pretool '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"swift test"}}' >/dev/null
run_pretool '{"tool_name":"Edit","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"file_path":"'"$TMPDIR_VDGG"'/.claude/.vdgg-state-test-id"}}' >/dev/null
POST_TASK=$(sed -n "$(grep -n '^task ' "$LOG" | tail -1 | cut -d: -f1),\$p" "$LOG" | grep -E '^(deny|stop|loop) ')
assert_eq "2" "$(printf '%s\n' "$POST_TASK" | grep -c .)" "two friction lines follow the last task marker, so showing only the last cannot pass"
write_state "$TMPDIR_VDGG" testing 7 0
SHOWN=$(vdgg_state_advance 6 reflection 2>&1 >/dev/null)
# Compare the whole block against the log itself. Drop only the state
# helper's own chatter, rather than listing the event words to keep: a
# display that leaked a `task` marker should fail, not be filtered clean.
SHOWN_FRICTION=$(printf '%s\n' "$SHOWN" | grep -v '^vdgg-state: ' || true)
assert_eq "$POST_TASK" "$SHOWN_FRICTION" "entering reflection shows every line after the last task marker and nothing before it"

# --- loops count the whole session, not the current task ---
# Step 8 -> 5 resets loop_count for the next task. The reset assert keeps the
# next one honest: without it, a report that read loop_count would also pass.
write_state "$TMPDIR_VDGG" progress 8 1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
assert_eq "0" "$(grep '^loop_count=' .claude/.vdgg-state-test-id | cut -d= -f2)" "8 to 5 resets loop_count"
REPORT=$(vdgg_friction_report)
assert_eq $'denies=4\nstops=1\nloops=1' "$REPORT" "report counts each event but not task markers; loops survive the 8 to 5 reset"

# --- clear hands back the same counts before it deletes the log ---
CLEAR_OUT=$(vdgg_state_clear 2>/dev/null)
assert_eq "$REPORT" "$CLEAR_OUT" "clear prints the report before deleting"
assert_file_not_exists "$LOG" "clear removes the friction log"

# --- init removes a previous session's leftover log ---
printf 'deny phase=implementing\n' > .claude/.vdgg-friction-stale-id
vdgg_state_init >/dev/null 2>&1
assert_file_not_exists ".claude/.vdgg-friction-stale-id" "init removes a stale friction log"
assert_eq $'denies=0\nstops=0\nloops=0' "$(vdgg_friction_report)" "a fresh session starts at zero"

exit 0
