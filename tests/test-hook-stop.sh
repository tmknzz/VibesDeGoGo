#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

STOPHOOK="$ROOT/skills/vibesdegogo/scripts/vdgg-hook-stop.sh"
TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

write_state() {
    mkdir -p "$TMPDIR_VDGG/.claude"
    echo "test-id" > "$TMPDIR_VDGG/.claude/.vdgg-active"
    cat > "$TMPDIR_VDGG/.claude/.vdgg-state-test-id" <<EOF
step=6
phase=implementing
loop_count=0
current_task=T
vdgg_id=test-id
last_updated=2026-05-25T00:00:00Z
EOF
}

run_hook() {
    local json="$1"
    set +e
    printf '%s' "$json" | bash "$STOPHOOK" >/tmp/vdgg-test-stop.out 2>/tmp/vdgg-test-stop.err
    local status=$?
    set -e
    echo "$status"
}

write_state
STATUS=$(run_hook '{"cwd":"'"$TMPDIR_VDGG"'"}')
assert_exit_code 0 "$STATUS" "missing transcript_path exits open"

TRANSCRIPT="$TMPDIR_VDGG/transcript.jsonl"
cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"continue"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"[Intentional Stop] waiting for validation"}]}}
EOF
STATUS=$(run_hook '{"cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$TRANSCRIPT"'"}')
assert_exit_code 0 "$STATUS" "intentional stop text is allowed"

cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"content":"continue"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}
EOF
STATUS=$(run_hook '{"cwd":"'"$TMPDIR_VDGG"'","transcript_path":"'"$TRANSCRIPT"'"}')
assert_exit_code 2 "$STATUS" "active workflow cannot stop silently"
