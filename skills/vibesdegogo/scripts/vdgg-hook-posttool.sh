#!/bin/bash
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &> /dev/null; then
    # VibesDeGoGo hook/state logic.
    # VibesDeGoGo hook/state logic.
    FALLBACK_TOOL=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
    FALLBACK_CMD=$(printf '%s' "$INPUT" | grep -oE '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"$/\1/')
    if command -v brew &> /dev/null; then
        ( brew install jq > /tmp/vdgg-jq-install.log 2>&1 & )
        echo "vdgg-hook-posttool: jq not found. Auto-installing in background (brew install jq, log: /tmp/vdgg-jq-install.log)。" >&2
    else
        echo "vdgg-hook-posttool: jq required but brew not found. Install jq manually." >&2
    fi
    if [ "$FALLBACK_TOOL" = "Bash" ] && printf '%s' "$FALLBACK_CMD" | grep -qE 'brew[[:space:]]+(install|reinstall)([[:space:]]|[^|;&])*[[:space:]]jq([[:space:]]|$)'; then
        exit 0
    fi
    echo "vdgg hook: jq is required. Install jq and retry." >&2
    exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // empty')

# VibesDeGoGo hook/state logic.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ]; then
    exit 0
fi

# VibesDeGoGo hook/state logic.
ACTIVE_FILE="$CWD/.claude/.vdgg-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    exit 0
fi

VDGG_ID=$(cat "$ACTIVE_FILE")
if [ -z "$VDGG_ID" ]; then
    exit 0
fi

# VibesDeGoGo hook/state logic.
STATE_FILE="$CWD/.claude/.vdgg-state-${VDGG_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT=$(grep "^loop_count=" "$STATE_FILE" | cut -d= -f2 || true)
LOOP_COUNT="${LOOP_COUNT:-0}"

if [ -z "$PHASE" ]; then
    exit 0
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$PHASE" != "testing" ]; then
    if [ "$TOOL_NAME" != "Bash" ]; then
        exit 0
    fi
else
    case "$TOOL_NAME" in
        Bash|Skill|Edit|Write)
            ;;
        *)
            exit 0
            ;;
    esac
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0')
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty')
STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
HOOK_ERROR=$(echo "$INPUT" | jq -r '.error // empty')

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$PHASE" = "testing" ] && [ "$TOOL_NAME" = "Skill" ]; then
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
    if [ "$SKILL_NAME" = "simplify" ]; then
        SENTINEL_FILE="$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}"
        if [ ! -f "$SENTINEL_FILE" ]; then
            STARTED_AT=$(date -u +%FT%TZ)
            cat > "$SENTINEL_FILE" <<EOF
started=1
started_at=${STARTED_AT}
modified=0
modified_files=
EOF
        fi
        exit 0
    fi
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$PHASE" = "testing" ] && { [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; }; then
    SENTINEL_FILE="$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}"
    if [ -f "$SENTINEL_FILE" ]; then
        EDITED_FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        # VibesDeGoGo hook/state logic.
        if [[ "$EDITED_FILE_PATH" == *"/.vdgg-state-"* ]] || [[ "$EDITED_FILE_PATH" == *"/.vdgg-active"* ]]; then
            exit 0
        fi
        # VibesDeGoGo hook/state logic.
        TASKS_DIR_BASENAME="tasks/vdgg/${VDGG_ID}"
        if [[ "$EDITED_FILE_PATH" == *"$TASKS_DIR_BASENAME"* ]]; then
            exit 0
        fi
        # VibesDeGoGo hook/state logic.
        CURRENT_FILES=$(grep '^modified_files=' "$SENTINEL_FILE" | head -1 | sed 's/^modified_files=//')
        if [ -n "$EDITED_FILE_PATH" ] && [[ ",$CURRENT_FILES," != *",$EDITED_FILE_PATH,"* ]]; then
            if [ -z "$CURRENT_FILES" ]; then
                NEW_FILES="$EDITED_FILE_PATH"
            else
                NEW_FILES="${CURRENT_FILES},${EDITED_FILE_PATH}"
            fi
        else
            NEW_FILES="$CURRENT_FILES"
        fi
        # VibesDeGoGo hook/state logic.
        TMP=$(mktemp)
        grep -v '^modified=' "$SENTINEL_FILE" | grep -v '^modified_files=' > "$TMP" || true
        cat >> "$TMP" <<EOF
modified=1
modified_files=${NEW_FILES}
EOF
        mv "$TMP" "$SENTINEL_FILE"
        exit 0
    fi
fi

if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

# VibesDeGoGo hook/state logic.
SEARCH_CMDS_PATTERN='(^|[[:space:];&|(])(grep|rg|ag|ack|find|awk|sed|fgrep|egrep|jq|test|\[)([[:space:]]|$)'
IS_SEARCH=0
if echo "$COMMAND" | grep -qE "$SEARCH_CMDS_PATTERN"; then
    IS_SEARCH=1
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if echo "$COMMAND" | grep -qE 'fo[a-z]_state_(init|write|advance|loop|clear|read)'; then
    exit 0
fi

# VibesDeGoGo hook/state logic.
ERROR_DETECTED=0
ERROR_REASON=""

if [ "$EXIT_CODE" -ne 0 ]; then
    # VibesDeGoGo hook/state logic.
    if [ "$IS_SEARCH" -eq 1 ] && [ "$EXIT_CODE" -lt 2 ]; then
        : # VibesDeGoGo hook/state logic.
    else
        ERROR_DETECTED=1
        ERROR_REASON="exit code=$EXIT_CODE"
    fi
fi

if [ "$ERROR_DETECTED" -eq 0 ] && [ "$HOOK_EVENT_NAME" = "PostToolUseFailure" ]; then
    ERROR_DETECTED=1
    if [ -n "$HOOK_ERROR" ]; then
        ERROR_REASON="$HOOK_ERROR"
    else
        ERROR_REASON="PostToolUseFailure"
    fi
fi

# VibesDeGoGo hook/state logic.
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDERR" | grep -qE '(^|[^a-zA-Z])(error|Error|ERROR|fail|Fail|FAIL|Exception|Traceback)([^a-zA-Z]|$)'; then
        ERROR_DETECTED=1
        ERROR_REASON="stderr matched error/fail/Exception pattern"
    fi
fi

# VibesDeGoGo hook/state logic.
if [ "$ERROR_DETECTED" -eq 0 ] && [ "$IS_SEARCH" -eq 0 ]; then
    if echo "$STDOUT" | grep -qE '^[[:space:]]*(error|Error|ERROR|fail|Fail|FAIL):[[:space:]]'; then
        ERROR_DETECTED=1
        ERROR_REASON="stdout started with error/fail pattern"
    fi
fi

# VibesDeGoGo hook/state logic.
if [ "$ERROR_DETECTED" -eq 1 ]; then
    FLAG_FILE="$CWD/.claude/.vdgg-error-pending"
    {
        echo "reason=$ERROR_REASON"
        echo "command=$COMMAND"
        echo "exit_code=$EXIT_CODE"
        if [ -n "$STDERR" ]; then
            echo "stderr_excerpt=$(echo "$STDERR" | head -c 500)"
        else
            echo "stderr_excerpt=$(echo "$HOOK_ERROR" | head -c 500)"
        fi
    } > "$FLAG_FILE"
fi

exit 0
