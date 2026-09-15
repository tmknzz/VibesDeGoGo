#!/bin/bash
# sentinel-fixtures.sh — shared review-sentinel fixture for hook gate tests.
# Usage: `. tests/lib/sentinel-fixtures.sh` then
#        write_review_sentinel <state-dir> <id> <loop> [modified] [modified_files]

write_review_sentinel() {
    local state_dir="$1" id="$2" loop="$3"
    local modified="${4:-0}" modified_files="${5:-}"
    cat > "${state_dir}/.vdgg-review-sentinel-${id}-${loop}" <<SENTINEL_EOF
started=1
started_at=2026-06-11T00:00:00Z
modified=${modified}
modified_files=${modified_files}
SENTINEL_EOF
}
