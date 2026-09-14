#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILED=0
TOTAL=0

# Every test runs under both shells. bash alone reports a full green on
# zsh-only breakage, so the zsh pass is the only thing that catches it; zsh is
# a hard requirement of the suite rather than an optional extra pass.
if ! command -v zsh >/dev/null 2>&1; then
    echo "error: zsh not found. The suite runs every test under bash and zsh." >&2
    echo "       Install it: brew install zsh / sudo apt-get install -y zsh" >&2
    exit 1
fi

for test_file in "$SCRIPT_DIR"/test-*.sh; do
    for sh in bash zsh; do
        TOTAL=$((TOTAL + 1))
        echo "==> $(basename "$test_file") [$sh]"
        if "$sh" "$test_file"; then
            echo "   PASS"
        else
            echo "   FAIL"
            FAILED=$((FAILED + 1))
        fi
    done
done

echo ""
echo "$TOTAL runs across bash and zsh, $FAILED failed"
[ "$FAILED" -eq 0 ]
