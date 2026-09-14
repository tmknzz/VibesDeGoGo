#!/bin/sh
# Bundled executor for the builtin "claude" formation value.
# Contract: VDGG_EXECUTOR_INPUT is the prompt file; with VDGG_EXECUTOR_OUTPUT
# set this is an artifact seat (effectively read-only: -p denies permission
# requests) writing the final message to that file; without it this is the
# Step 6 editing seat and may edit the working tree.
set -eu

input=${VDGG_EXECUTOR_INPUT:-}
output=${VDGG_EXECUTOR_OUTPUT:-}
[ -f "$input" ] || { echo "vdgg-exec-claude: input is missing" >&2; exit 64; }
command -v claude >/dev/null 2>&1 || { echo "vdgg-exec-claude: claude CLI is required" >&2; exit 69; }

model=${VDGG_EXECUTOR_MODEL:-sonnet}
effort=${VDGG_EXECUTOR_EFFORT:-}

# --safe-mode: this is a tool being handed a prompt, not a participant in the
# caller's VibesDeGoGo! session. Without it the subprocess inherits the target
# repo's CLAUDE.md and skills, reads the VDGG skill, and answers as a workflow
# participant ("[Intentional Stop] ...") instead of producing the artifact.
# Auth, model selection, built-in tools and permissions still work normally.
set -- -p --safe-mode --model "$model"
[ -n "$effort" ] && set -- "$@" --effort "$effort"

if [ -n "$output" ]; then
  # --permission-prompts none: an artifact seat is contracted to write its
  # result to stdout, so a tool call that would prompt has no one to answer
  # it. Refuse such calls outright instead of leaving the run hanging on an
  # approval that never arrives.
  claude "$@" --permission-prompts none < "$input" > "$output"
else
  claude "$@" --permission-mode acceptEdits < "$input" >/dev/null
fi
