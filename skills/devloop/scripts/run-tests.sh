#!/usr/bin/env sh
# run-tests.sh — run all skill tests; exit non-zero on first failure
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FAIL=0
PASS_FILES=0
for t in "$ROOT"/tests/*.test.sh; do
  [ -f "$t" ] || continue
  if sh "$t"; then
    PASS_FILES=$((PASS_FILES + 1))
  else
    printf 'FAIL %s\n' "$t" >&2
    FAIL=1
  fi
done
printf 'files_passed=%s\n' "$PASS_FILES"
[ "$FAIL" -eq 0 ]
