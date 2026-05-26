#!/bin/bash
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
        echo "vdgg hook: jq is required. Install jq and retry." >&2
    else
        echo "vdgg-hook-pretool: jq required but brew not found. Install jq manually." >&2
    fi
    if [ "$FALLBACK_TOOL" = "Bash" ] && printf '%s' "$FALLBACK_CMD" | grep -qE 'brew[[:space:]]+(install|reinstall)([[:space:]]|[^|;&])*[[:space:]]jq([[:space:]]|$)'; then
        exit 0
    fi
    echo "vdgg hook: jq is required. Install jq and retry." >&2
    exit 2
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

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
TASKS_DIR="$CWD/tasks/vdgg/${VDGG_ID}"

# VibesDeGoGo hook/state logic.

case "$TOOL_NAME" in
    Edit|Write)
        FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        ;;
    Bash)
        COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        ;;
    Agent)
        # VibesDeGoGo hook/state logic.
        ;;
    *)
        # VibesDeGoGo hook/state logic.
        exit 0
        ;;
esac

# VibesDeGoGo hook/state logic.
ERROR_FLAG="$CWD/.claude/.vdgg-error-pending"
if [ -f "$ERROR_FLAG" ]; then
    TRANSCRIPT_PATH_E=$(echo "$INPUT" | jq -r '.transcript_path // empty')
    if [ -n "$TRANSCRIPT_PATH_E" ] && [ -f "$TRANSCRIPT_PATH_E" ]; then
        LAST_USER_LINE_E=$(jq -r 'select(.type=="user" and ((.message.content | type) == "string" or ((.message.content | type) == "array" and (.message.content[0].type // "") != "tool_result"))) | input_line_number' "$TRANSCRIPT_PATH_E" 2>/dev/null | tail -1)
        LAST_USER_LINE_E="${LAST_USER_LINE_E:-0}"
        CURRENT_TURN_TEXT_E=$(awk -v start="$LAST_USER_LINE_E" 'NR > start' "$TRANSCRIPT_PATH_E" | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)
        if echo "$CURRENT_TURN_TEXT_E" | grep -qF "[Error Acknowledged]"; then
            rm -f "$ERROR_FLAG"
        else
            ERROR_REASON=$(grep "^reason=" "$ERROR_FLAG" | cut -d= -f2- || echo "unknown")
            echo "VibesDeGoGo! [${VDGG_ID}]: Previous Bash command failed ($ERROR_REASON). Output [Error Acknowledged] with a short plan before running another tool." >&2
            exit 2
        fi
    fi
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
    if [[ "$FILE_PATH" == *"/.claude/.vdgg-state-"* ]] || [[ "$FILE_PATH" == *"/.claude/.vdgg-active" ]] \
        || [[ "$FILE_PATH" == *".claude/.vdgg-state-"* ]] || [[ "$FILE_PATH" == *".claude/.vdgg-active" ]]; then
        echo "VibesDeGoGo! [${VDGG_ID}]: Direct state-file edits are blocked. Use vdgg_state_* helpers." >&2
        exit 2
    fi
fi
if [ "$TOOL_NAME" = "Bash" ]; then
    # VibesDeGoGo hook/state logic.
    # `git commit` is exempt: the command text may legitimately mention state-file
    # paths inside the commit message, and git commit does not write to those
    # tracked files directly. Commit phase rules and the implementing/testing
    # commit-blocking pattern still apply elsewhere.
    if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
        :
    elif echo "$COMMAND" | grep -qE '(\.claude/\.vdgg-state-|\.claude/\.vdgg-active)'; then
        # VibesDeGoGo hook/state logic.
        # `>[^&]` excludes fd-merge redirects (2>&1, >&2) which are not destructive.
        if echo "$COMMAND" | grep -qE '(>[^&]|tee[[:space:]]|sed[[:space:]]+-i|mv[[:space:]]|cp[[:space:]]|rm[[:space:]])'; then
            echo "VibesDeGoGo! [${VDGG_ID}]: Direct state-file edits are blocked. Use vdgg_state_* helpers." >&2
            exit 2
        fi
    fi
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
#
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
#
# VibesDeGoGo hook/state logic.
#
# VibesDeGoGo hook/state logic.
#   # [VibesDeGoGo! Step 3 Start] step=3, phase=investigating, loop=0
#   source $HOME/.claude/skills/vibesdegogo/scripts/vdgg-state.sh && vdgg_state_advance 3 investigating
#
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$TOOL_NAME" = "Bash" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+'; then
    TRANSITION_COUNT=$(printf '%s\n' "$COMMAND" | grep -oE 'vdgg_state_(advance|loop)[[:space:]]+[0-9]+' | wc -l | tr -d ' ')
    if [ "${TRANSITION_COUNT:-0}" -gt 1 ]; then
        echo "VibesDeGoGo! [${VDGG_ID}]: State transition commands must include the matching VibesDeGoGo! Step declaration." >&2
        exit 2
    fi
    TARGET_STEP=$(echo "$COMMAND" | sed -nE 's/.*vdgg_state_(advance|loop|write)[[:space:]]+([0-9]+).*/\2/p' | head -1)
    if [ -n "$TARGET_STEP" ]; then
        DECL_OK=0
        if echo "$COMMAND" | grep -qF "[VibesDeGoGo! Step ${TARGET_STEP} Start]"; then
            DECL_OK=1
        elif [ "$TARGET_STEP" = "2" ] && echo "$COMMAND" | grep -qF '[VibesDeGoGo! Declaration]'; then
            DECL_OK=1
        fi
        if [ "$DECL_OK" -eq 0 ]; then
            echo "VibesDeGoGo! [${VDGG_ID}]: State transition commands must include the matching VibesDeGoGo! Step declaration." >&2
            exit 2
        fi
    fi
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "implementing" ]; then
    TEST_PATTERN_DEFAULT='swift[[:space:]]+test|xcodebuild[[:space:]]+[^|]*[[:space:]]test|pytest|npm[[:space:]]+(run[[:space:]]+)?test|pnpm[[:space:]]+(run[[:space:]]+)?test|yarn[[:space:]]+(run[[:space:]]+)?test|go[[:space:]]+test|cargo[[:space:]]+test|jest|vitest|mocha'
    TEST_PATTERN_EXTRA=""
    if [ -f "$CWD/.vdgg-target" ]; then
        TEST_PATTERN_EXTRA=$(grep '^TEST_COMMAND_PATTERN=' "$CWD/.vdgg-target" 2>/dev/null | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/' | head -1)
    fi
    TEST_PATTERN="$TEST_PATTERN_DEFAULT"
    if [ -n "$TEST_PATTERN_EXTRA" ]; then
        TEST_PATTERN="${TEST_PATTERN}|${TEST_PATTERN_EXTRA}"
    fi
    if echo "$COMMAND" | grep -qE "(^|[[:space:];&|(])(${TEST_PATTERN})([[:space:]]|$)"; then
        echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
        exit 2
    fi
fi

# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
# VibesDeGoGo hook/state logic.
if [ "$PHASE" = "implementing" ] || [ "$PHASE" = "testing" ]; then
    if [ "$LOOP_COUNT" -ge 99 ]; then
        echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
        exit 2
    fi
fi

# VibesDeGoGo hook/state logic.

case "$PHASE" in
    declare|requirements)
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Agent" ]; then
            echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
            exit 2
        fi
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == */${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == ${TASKS_DIR}/* ]]; then
                    exit 0
                fi
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
        fi
        # VibesDeGoGo hook/state logic.
        # VibesDeGoGo hook/state logic.
        if [ "$PHASE" = "requirements" ] && [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+3[[:space:]]+investigating([[:space:]]|$)'; then
                REQ_FILE="${TASKS_DIR}/requirements.md"
                if [ ! -f "$REQ_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (requirements) [${VDGG_ID}]: requirements.md is required before investigation." >&2
                    exit 2
                fi
            fi
        fi
        ;;

    investigating|planning)
        # VibesDeGoGo hook/state logic.
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == */${TASKS_DIR}/* ]] || [[ "$FILE_PATH" == ${TASKS_DIR}/* ]]; then
                    exit 0
                fi
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
        fi
        ;;

    task-selected)
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
            exit 2
        fi
        ;;

    implementing|testing)
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Bash" ]; then
            if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit($|[[:space:]])'; then
                echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                exit 2
            fi
            # VibesDeGoGo hook/state logic.
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+[0-9]+[[:space:]]+implementing'; then
                echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                exit 2
            fi
            # VibesDeGoGo hook/state logic.
            if [ "$PHASE" = "testing" ] && echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                SENTINEL_FILE="$CWD/.claude/.vdgg-simplify-sentinel-${VDGG_ID}-${LOOP_COUNT}"
                if [ ! -f "$SENTINEL_FILE" ]; then
                    echo "VibesDeGoGo! [${VDGG_ID:-unknown}]: Tool call blocked by VibesDeGoGo! hook." >&2
                    exit 2
                fi
                MODIFIED=$(grep '^modified=' "$SENTINEL_FILE" | head -1 | sed 's/^modified=//')
                if [ "$MODIFIED" = "1" ]; then
                    MODIFIED_FILES=$(grep '^modified_files=' "$SENTINEL_FILE" | head -1 | sed 's/^modified_files=//')
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                # VibesDeGoGo hook/state logic.
                rm -f "$SENTINEL_FILE"
            fi
        fi
        ;;

    reflection)
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if [ -n "$FILE_PATH" ]; then
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]] \
                    || [[ "$FILE_PATH" == "${TASKS_DIR}"/investigation-r*.md ]]; then
                    exit 0
                fi
            fi
            echo "VibesDeGoGo! reflection [${VDGG_ID}]: Reflection must update retry investigation and progress before returning to implementation." >&2
            exit 2
        fi
        # VibesDeGoGo hook/state logic.
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Bash" ]; then
            # VibesDeGoGo hook/state logic.
            if echo "$COMMAND" | grep -qE 'vdgg_state_(advance|loop|write)[[:space:]]+[0-9]+[[:space:]]+verified'; then
                echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                exit 2
            fi
            if echo "$COMMAND" | grep -qE 'vdgg_state_(loop|advance|write)[[:space:]]+6[[:space:]]+implementing'; then
                PROGRESS_FILE="${TASKS_DIR}/progress.md"
                RETRY_INVESTIGATION_FILE="${TASKS_DIR}/investigation-r${LOOP_COUNT}.md"
                if [ ! -f "$RETRY_INVESTIGATION_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                if [ ! -f "$PROGRESS_FILE" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                STATE_MTIME=$(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0)
                RETRY_INVESTIGATION_MTIME=$(stat -f %m "$RETRY_INVESTIGATION_FILE" 2>/dev/null || echo 0)
                PROGRESS_MTIME=$(stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo 0)
                if [ "$RETRY_INVESTIGATION_MTIME" -le "$STATE_MTIME" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
                if [ "$PROGRESS_MTIME" -le "$STATE_MTIME" ]; then
                    echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
                    exit 2
                fi
            fi
        fi
        ;;

    verified|progress|commit)
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
            if { [ "$PHASE" = "progress" ] || [ "$PHASE" = "commit" ]; } && [ -n "$FILE_PATH" ]; then
                # VibesDeGoGo hook/state logic.
                if [[ "$FILE_PATH" == "${TASKS_DIR}/progress.md" ]]; then
                    exit 0
                fi
                # VibesDeGoGo hook/state logic.
                TARGET_FILE="$CWD/.vdgg-target"
                if [ -f "$TARGET_FILE" ]; then
                    ALLOWED_PATHS=$(grep -E '^VERSION_FILE_[0-9]+_PATH=' "$TARGET_FILE" \
                        | sed -E 's/^[^=]*=//' \
                        | sed -E 's/^"(.*)"$/\1/' \
                        | sed -E "s/^'(.*)'\$/\\1/" \
                        | grep -v '^$' || true)
                    while IFS= read -r allowed; do
                        [ -z "$allowed" ] && continue
                        if [[ "$FILE_PATH" == "${allowed}" ]] \
                            || [[ "$FILE_PATH" == "$CWD/${allowed}" ]]; then
                            exit 0
                        fi
                    done <<< "$ALLOWED_PATHS"
                fi
            fi
            echo "VibesDeGoGo! Step ${STEP} (${PHASE}) [${VDGG_ID}]: This action is blocked in the current phase." >&2
            exit 2
        fi
        # VibesDeGoGo hook/state logic.
        if [ "$TOOL_NAME" = "Bash" ] && [ "$PHASE" = "commit" ]; then
            # VibesDeGoGo hook/state logic.
            WF=branch-pr; BB=""
            if [ -f "$CWD/.vdgg-target" ]; then
                WF=$( { grep -E '^WORKFLOW=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                BB=$( { grep -E '^BASE_BRANCH=' "$CWD/.vdgg-target" 2>/dev/null || true; } | tail -1 | sed -E 's/^[^=]*=//; s/^"//; s/"$//')
                WF=${WF:-branch-pr}
            fi
            if [ "$WF" != "trunk" ]; then
                if [ -z "$BB" ]; then
                    BB=$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)
                    BB=${BB#origin/}
                    BB=${BB:-main}
                fi
                CURBR=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
                # VibesDeGoGo hook/state logic.
                # VibesDeGoGo hook/state logic.
                # VibesDeGoGo hook/state logic.
                BB_RE=$(printf '%s' "$BB" | sed 's/[^[:alnum:]]/\\&/g')
                if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+(commit|push)([[:space:]]|$)'; then
                    if [ "$CURBR" = "$BB" ]; then
                        echo "VibesDeGoGo! Step ${STEP} (commit) [${VDGG_ID}]: branch-pr workflow requires committing/pushing the feature branch and opening a PR." >&2
                        exit 2
                    fi
                    if echo "$COMMAND" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+push' \
                        && echo "$COMMAND" | grep -qE "(^|[^a-zA-Z0-9_/.-])${BB_RE}([^a-zA-Z0-9_/.-]|\$)"; then
                        echo "VibesDeGoGo! Step ${STEP} (commit) [${VDGG_ID}]: branch-pr workflow requires committing/pushing the feature branch and opening a PR." >&2
                        exit 2
                    fi
                fi
            fi
        fi
        ;;
esac

exit 0
