#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DOCTOR="$TEST_DIR/../scripts/doctor.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/adr-doctor.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$DOCTOR"; then ok 'sh -n doctor.sh'; else not_ok 'sh -n doctor.sh'; fi

if sh "$DOCTOR" >/dev/null 2>&1; then
  ok 'doctor passes on real skill tree'
else
  not_ok 'doctor passes on real skill tree'
fi

# Broken tree: missing SKILL.md should fail
mkdir -p "$TMP/scripts/lib" "$TMP/references"
cp "$TEST_DIR/../scripts/lib/common.sh" "$TMP/scripts/lib/"
cp "$DOCTOR" "$TMP/scripts/doctor.sh"
cp "$TEST_DIR/../scripts/detect-runtime-host.sh" "$TMP/scripts/"
cp "$TEST_DIR/../scripts/launch-runner-template.sh" "$TMP/scripts/"
# no SKILL.md / ROADMAP / templates
if sh "$TMP/scripts/doctor.sh" >/dev/null 2>&1; then
  not_ok 'doctor fails on incomplete tree'
else
  ok 'doctor fails on incomplete tree'
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
