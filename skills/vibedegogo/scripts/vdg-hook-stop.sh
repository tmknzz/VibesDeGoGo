#!/bin/bash
# VibeDeGoGo hook/state logic.
#
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
#
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.

set -euo pipefail

INPUT=$(cat)

if ! command -v jq &> /dev/null; then
    exit 0 # VibeDeGoGo hook/state logic.
fi

# VibeDeGoGo hook/state logic.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
# VibeDeGoGo hook/state logic.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -z "$CWD" ] || [ ! -d "$CWD" ]; then
    exit 0
fi

# VibeDeGoGo hook/state logic.
ACTIVE_FILE="$CWD/.claude/.vdg-active"
if [ ! -f "$ACTIVE_FILE" ]; then
    exit 0
fi

VDG_ID=$(cat "$ACTIVE_FILE")
if [ -z "$VDG_ID" ]; then
    exit 0
fi

STATE_FILE="$CWD/.claude/.vdg-state-${VDG_ID}"
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

PHASE=$(grep "^phase=" "$STATE_FILE" | cut -d= -f2 || true)
STEP=$(grep "^step=" "$STATE_FILE" | cut -d= -f2 || true)

# VibeDeGoGo hook/state logic.
LAST_USER_LINE=$(jq -r 'select(.type=="user" and ((.message.content | type) == "string" or ((.message.content | type) == "array" and (.message.content[0].type // "") != "tool_result"))) | input_line_number' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
LAST_USER_LINE="${LAST_USER_LINE:-0}"

# VibeDeGoGo hook/state logic.
CURRENT_TURN_TEXT=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text // empty' 2>/dev/null || true)

# VibeDeGoGo hook/state logic.
CURRENT_TURN_BASH=$(awk -v start="$LAST_USER_LINE" 'NR > start' "$TRANSCRIPT_PATH" \
    | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Bash") | .input.command // empty' 2>/dev/null || true)

# VibeDeGoGo hook/state logic.
if echo "$CURRENT_TURN_BASH" | grep -qE 'vdg_state_(advance|loop|write|clear|init)'; then
    exit 0
fi

# VibeDeGoGo hook/state logic.
if echo "$CURRENT_TURN_TEXT" | grep -qF "[Intentional Stop]"; then
    exit 0
fi

# VibeDeGoGo hook/state logic.
echo "VibeDeGoGo! [${VDG_ID}] step=${STEP} phase=${PHASE}: Active workflow cannot stop silently. Run the next state action or output [Intentional Stop] with a reason." >&2
exit 2
