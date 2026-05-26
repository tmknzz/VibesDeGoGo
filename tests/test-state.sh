#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

TMPDIR_VDGG=$(mktemp -d)
trap 'rm -rf "$TMPDIR_VDGG"' EXIT

cd "$TMPDIR_VDGG" || exit 1
VDGG_CWD="$TMPDIR_VDGG"
source "$ROOT/skills/vibesdegogo/scripts/vdgg-state.sh"

vdgg_state_init >/tmp/vdgg-test-state-init.out 2>/tmp/vdgg-test-state-init.err
ID=$(vdgg_get_id)
assert_ne "" "$ID" "vdgg_state_init creates an id"
assert_file_exists ".claude/.vdgg-active" "active file exists"
assert_file_exists ".claude/.vdgg-state-${ID}" "state file exists"

set +e
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-bad.out 2>/tmp/vdgg-test-state-bad.err
BAD_STATUS=$?
set -e
assert_exit_code 1 "$BAD_STATUS" "invalid step jump is rejected"
CURRENT_STEP=$(grep '^step=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "1" "$CURRENT_STEP" "invalid transition leaves state unchanged"

vdgg_state_advance 2 requirements >/tmp/vdgg-test-state-2.out 2>/tmp/vdgg-test-state-2.err
vdgg_state_advance 3 investigating >/tmp/vdgg-test-state-3.out 2>/tmp/vdgg-test-state-3.err
vdgg_state_advance 4 planning >/tmp/vdgg-test-state-4.out 2>/tmp/vdgg-test-state-4.err
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-5.out 2>/tmp/vdgg-test-state-5.err
vdgg_state_advance 6 implementing >/tmp/vdgg-test-state-6.out 2>/tmp/vdgg-test-state-6.err
vdgg_state_loop 6 implementing >/tmp/vdgg-test-state-loop.out 2>/tmp/vdgg-test-state-loop.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "1" "$LOOP_COUNT" "vdgg_state_loop increments loop_count"

vdgg_state_advance 7 testing >/tmp/vdgg-test-state-7.out 2>/tmp/vdgg-test-state-7.err
vdgg_state_mark_reviewed >/tmp/vdgg-test-state-review.out 2>/tmp/vdgg-test-state-review.err
assert_file_exists ".claude/.vdgg-review-sentinel-${ID}-1" "mark_reviewed creates review sentinel"
REVIEWED=$(grep '^reviewed=' ".claude/.vdgg-review-sentinel-${ID}-1" | cut -d= -f2)
assert_eq "1" "$REVIEWED" "review sentinel records reviewed=1"

vdgg_state_advance 8 progress >/tmp/vdgg-test-state-8.out 2>/tmp/vdgg-test-state-8.err
vdgg_state_advance 5 task-selected >/tmp/vdgg-test-state-8to5.out 2>/tmp/vdgg-test-state-8to5.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "0" "$LOOP_COUNT" "8 to 5 resets loop_count"

vdgg_state_advance 6 implementing >/tmp/vdgg-test-state-6b.out 2>/tmp/vdgg-test-state-6b.err
vdgg_state_write 7 testing 2 >/tmp/vdgg-test-state-write7.out 2>/tmp/vdgg-test-state-write7.err
vdgg_state_advance 6 reflection >/tmp/vdgg-test-state-7to6.out 2>/tmp/vdgg-test-state-7to6.err
LOOP_COUNT=$(grep '^loop_count=' ".claude/.vdgg-state-${ID}" | cut -d= -f2)
assert_eq "2" "$LOOP_COUNT" "7 to 6 preserves loop_count"

vdgg_state_clear >/tmp/vdgg-test-state-clear.out 2>/tmp/vdgg-test-state-clear.err
assert_file_not_exists ".claude/.vdgg-active" "clear removes active file"
assert_file_not_exists ".claude/.vdgg-state-${ID}" "clear removes state file"
assert_file_not_exists ".claude/.vdgg-review-sentinel-${ID}-1" "clear removes review sentinels"
