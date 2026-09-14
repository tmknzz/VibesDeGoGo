#!/bin/bash
# test-investigation-headings-drift.sh — cross-file drift test for the seven
# required Step 3 investigation.md headings. Pins that every source that
# encodes the heading list agrees, so a rename in one place cannot silently
# drift from the others.
#
# The canonical seven heading strings live here as one bash array. Each source
# below must contain each string in one of the two accepted forms:
#   `## N. Title`        (markdown / SKILL.md / subagent_prompts.md)
#   `## N\. Title`       (awk regex source embedded in the hook scripts)
#
# Encoding the list in the test itself rather than extracting it with a regex
# avoids making the extractor a de-facto sixth source of truth (a punctuated
# or non-ASCII rename would silently drop from every fuzzy extractor's output).

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"

REQUIRED_HEADINGS=(
    "## 1. Related files"
    "## 2. Existing implementation patterns"
    "## 3. Impact surface"
    "## 4. Prior similar implementations"
    "## 5. Side effects and risks"
    "## 6. Constraints"
    "## 7. Verification strategy"
)

SOURCES=(
    "skills/vibesdegogo/references/subagent_prompts.md"
    "skills/vibesdegogo/SKILL.md"
    "skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
    ".agents/skills/vibesdegogo/SKILL.md"
    ".agents/skills/vibesdegogo/scripts/vdgg-hook-pretool.sh"
)

for src in "${SOURCES[@]}"; do
    file="$ROOT/$src"
    for h in "${REQUIRED_HEADINGS[@]}"; do
        # Try the markdown form first, then the awk-regex form ('.' -> '\.').
        h_awk=${h//./\\.}
        if grep -qF "$h" "$file" || grep -qF "$h_awk" "$file"; then
            :  # present
        else
            fail "drift: '$h' missing from ${src} (neither markdown nor awk-regex form found)"
        fi
    done
done

echo "drift: all ${#REQUIRED_HEADINGS[@]} headings present in ${#SOURCES[@]} sources"
