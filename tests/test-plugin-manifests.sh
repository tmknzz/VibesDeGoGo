#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available for manifest validation" >&2
    exit 0
fi

# Manifests parse as valid JSON.
jq -e . "$ROOT/.claude-plugin/plugin.json" >/dev/null || fail "plugin.json is not valid JSON"
jq -e . "$ROOT/.claude-plugin/marketplace.json" >/dev/null || fail "marketplace.json is not valid JSON"
jq -e . "$ROOT/hooks/hooks.json" >/dev/null || fail "hooks.json is not valid JSON"

# Required fields are present.
NAME=$(jq -r '.name' "$ROOT/.claude-plugin/plugin.json")
assert_eq "vibesdegogo" "$NAME" "plugin.json name"
MP_PLUGIN=$(jq -r '.plugins[0].name' "$ROOT/.claude-plugin/marketplace.json")
assert_eq "vibesdegogo" "$MP_PLUGIN" "marketplace.json plugin entry"

# Every hook command references a script that exists in the repo.
while IFS= read -r cmd; do
    rel=${cmd#*\$\{CLAUDE_PLUGIN_ROOT\}\"/}
    rel=${rel%%[\"\ ]*}
    assert_file_exists "$ROOT/$rel" "hook script referenced by hooks.json exists"
done < <(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json")

# plugin.json version matches SKILL.md version.
PLUGIN_VERSION=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
SKILL_VERSION=$(grep '^version:' "$ROOT/skills/vibesdegogo/SKILL.md" | awk '{print $2}')
assert_eq "$PLUGIN_VERSION" "$SKILL_VERSION" "plugin.json version matches SKILL.md"

# hooks.json と setup.md が同じスクリプト集合を参照していること。
HOOKS_SCRIPTS=$(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json" \
    | grep -oE 'vdgg-hook-[a-z]+\.sh' | sort -u)
SETUP_SCRIPTS=$(grep -oE 'vdgg-hook-[a-z]+\.sh' \
    "$ROOT/skills/vibesdegogo/references/setup.md" | sort -u)
assert_eq "$HOOKS_SCRIPTS" "$SETUP_SCRIPTS" \
    "hooks.json and setup.md reference the same hook scripts"

# plugin.json と marketplace.json の plugin 説明文が一致すること。
PLUGIN_DESC=$(jq -r '.description' "$ROOT/.claude-plugin/plugin.json")
MP_DESC=$(jq -r '.plugins[0].description' "$ROOT/.claude-plugin/marketplace.json")
assert_eq "$PLUGIN_DESC" "$MP_DESC" "plugin description matches marketplace entry"

# 各イベントの matcher が意図どおりであること。PreToolUse は空文字を保つ:
# vdgg-hook-pretool.sh は file_path / notebook_path を持つ未知ツールも
# 検査するので、既知ツールの列挙に絞るとそのガードを迂回できてしまう。
assert_matcher() {
    local event="$1" expected="$2" actual
    actual=$(jq -r --arg e "$event" '.hooks[$e][].matcher' "$ROOT/hooks/hooks.json")
    assert_eq "$expected" "$actual" "hooks.json ${event} matcher"
}
assert_matcher PreToolUse ""
assert_matcher PostToolUse "Bash|Skill|Edit|Write"
assert_matcher PostToolUseFailure "Bash|Skill|Edit|Write"
assert_matcher Stop ""
