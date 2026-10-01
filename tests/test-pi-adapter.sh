#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
node --test tests/pi/*.test.mjs
