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

# --- pretool: one refusal appends one deny line that names its gate ---
write_state "$TMPDIR_VDGG" implementing 6 0
run_pretool '{"tool_name":"Bash","cwd":"'"$TMPDIR_VDGG"'","tool_input":{"command":"swift test"}}' >/dev/null
assert_eq "1" "$(count deny)" "one refusal appends one deny line"
LINE=$(grep '^deny ' "$LOG" | head -1)
assert_contains "$LINE" "phase=implementing" "deny line records the phase"
assert_contains "$LINE" "tool=Bash" "deny line records the tool"
GATE=$(printf '%s' "$LINE" | sed -n 's/.*gate=\([0-9][0-9]*\)$/\1/p')
assert_ne "" "$GATE" "deny line records a gate line number"
assert_contains "$(sed -n "${GATE}p" "$PRETOOL")" "exit 2" "gate points at the exit that refused"

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

# --- loops count the whole session, not the current task ---
# Step 8 -> 5 resets loop_count for the next task. The reset assert keeps the
# next one honest: without it, a report that read loop_count would also pass.
write_state "$TMPDIR_VDGG" progress 8 1
vdgg_state_advance 5 task-selected >/dev/null 2>&1
assert_eq "0" "$(grep '^loop_count=' .claude/.vdgg-state-test-id | cut -d= -f2)" "8 to 5 resets loop_count"
REPORT=$(vdgg_friction_report)
assert_eq $'denies=1\nstops=1\nloops=1' "$REPORT" "report counts each event; loops survive the 8 to 5 reset"

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
