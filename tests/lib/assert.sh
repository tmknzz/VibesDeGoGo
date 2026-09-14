#!/bin/bash

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [ "$expected" = "$actual" ] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_ne() {
    local not_expected="$1" actual="$2" message="$3"
    [ "$not_expected" != "$actual" ] || fail "${message}: did not expect '${actual}'"
}

assert_exit_code() {
    local expected="$1" actual="$2" message="$3"
    # zsh evaluates `[ 0 -eq "" ]` as true, so a helper that aborted mid-way and
    # returned nothing would otherwise be recorded as a pass.
    case "$actual" in ''|*[!0-9]*) fail "${message}: non-numeric exit code '${actual}'" ;; esac
    [ "$expected" -eq "$actual" ] || fail "${message}: expected exit ${expected}, got ${actual}"
}

# zsh ties the name `path` to $PATH, so `local path=...` empties PATH for the
# duration of the function. Use a name that is not special in either shell.
assert_file_exists() {
    local target="$1" message="$2"
    [ -e "$target" ] || fail "${message}: missing ${target}"
}

assert_file_not_exists() {
    local target="$1" message="$2"
    [ ! -e "$target" ] || fail "${message}: unexpected ${target}"
}

assert_contains() {
    local haystack="$1" needle="$2" message="$3"
    case "$haystack" in
        *"$needle"*) ;;
        *) fail "${message}: '${needle}' not found" ;;
    esac
}
