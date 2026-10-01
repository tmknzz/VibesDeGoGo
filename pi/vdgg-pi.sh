#!/bin/sh
set -eu
edition=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
core="$edition/../.agents/skills/vibesdegogo"
pi_bin=${VDGG_PI_BIN:-pi}
qwenmagi=${QWENMAGI_SKILL_DIR:-$HOME/.agents/skills/qwenmagi}
for resource in "$core/scripts/vdgg-state.sh" "$core/scripts/vdgg-hook-pretool.sh" "$core/scripts/vdgg-hook-posttool.sh" "$core/scripts/vdgg-hook-stop.sh" "$core/scripts/vdgg-evidence.sh" "$qwenmagi/SKILL.md"; do
  [ -f "$resource" ] || { echo "vdgg-pi: required resource missing: $resource" >&2; exit 69; }
done
command -v "$pi_bin" >/dev/null 2>&1 || { echo 'vdgg-pi: set VDGG_PI_BIN to the pi executable' >&2; exit 69; }
command -v jq >/dev/null 2>&1 || { echo 'vdgg-pi: jq is required' >&2; exit 69; }
root=$(git rev-parse --show-toplevel)
cd "$root"
export VDGG_CODEX_SKILL_DIR="$core"
export QWENMAGI_PI_BIN="${QWENMAGI_PI_BIN:-$pi_bin}"
unset VDGG_CWD VDGG_STATE_DIR VDGG_TASKS_DIR
exec "$pi_bin" --no-extensions --extension "$edition/extensions/vdgg.mjs" \
  --no-skills --skill "$edition/skills/vibesdegogo-pi/SKILL.md" \
  --skill "$qwenmagi/SKILL.md" --tools read,bash,edit,write "$@"
