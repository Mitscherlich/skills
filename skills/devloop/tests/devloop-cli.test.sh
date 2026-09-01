#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DL="$TEST_DIR/../scripts/devloop"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-cli.test.XXXXXX") || exit 1
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT HUP INT TERM

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$DL"; then ok 'sh -n devloop'; else not_ok 'sh -n devloop'; fi

ver=$(sh "$DL" version)
[ "$ver" = "0.6.0" ] && ok 'version 0.6.0' || not_ok 'version 0.6.0'

if sh "$DL" help >/dev/null; then ok 'help exits 0'; else not_ok 'help exits 0'; fi


if sh "$DL" detect-scheduler --coordinator grok >/dev/null; then
  ok 'detect-scheduler via devloop'
else
  not_ok 'detect-scheduler via devloop'
fi

if sh "$DL" cleanup-sessions --help >/dev/null 2>&1; then
  not_ok 'cleanup-sessions help exits 2'
else
  ok 'cleanup-sessions help exits 2'
fi
if sh "$DL" doctor >/dev/null; then ok 'doctor via devloop'; else not_ok 'doctor via devloop'; fi

id=$(sh "$DL" attempt new --prefix cli)
case "$id" in cli-*) ok 'attempt via devloop' ;; *) not_ok 'attempt via devloop' ;; esac

if sh "$DL" state can --from open --to implementing; then
  ok 'state via devloop'
else
  not_ok 'state via devloop'
fi

if sh "$DL" stage can --from intent --to spec; then
  ok 'stage can via devloop'
else
  not_ok 'stage can via devloop'
fi
if sh "$DL" stage can --from intent --to plan; then
  not_ok 'stage rejects level skip'
else
  ok 'stage rejects level skip'
fi
if sh "$DL" stage nope --from intent >/dev/null 2>&1; then
  not_ok 'unknown stage subcommand rejected'
else
  ok 'unknown stage subcommand rejected'
fi

init_out=$(sh "$DL" init --id 0007-cli --title cli --root "$TMP/dlroot")
echo "$init_out" | grep -q '^stage=intent$' && ok 'init via devloop' || not_ok 'init via devloop'
if sh "$DL" gate intent --file "$TMP/dlroot/0007-cli/intent.md" >/dev/null 2>&1; then
  not_ok 'gate via devloop rejects unfilled template'
else
  ok 'gate via devloop rejects unfilled template'
fi

nd=$(sh "$DL" next --dir "$TMP/dlroot/0007-cli")
echo "$nd" | grep -qx 'action=grill_intent' && ok 'next --dir routes to grill' || not_ok 'next --dir routes to grill'
echo "$nd" | grep -q '^fail=' && ok 'next --dir surfaces gate failures' || not_ok 'next --dir surfaces gate failures'

cat >"$TMP/plan.md" <<'EOF'
| F1 | a | open | x | y |
EOF
out=$(sh "$DL" status --plan "$TMP/plan.md")
echo "$out" | grep -qx 'open_id=F1' && ok 'status via devloop' || not_ok 'status via devloop'

out2=$(sh "$DL" next --plan "$TMP/plan.md")
echo "$out2" | grep -qx 'action=work_open_slice' && ok 'next via devloop' || not_ok 'next via devloop'

mkdir -p "$TMP/dl"
cp "$TMP/plan.md" "$TMP/dl/plan.md"
if sh "$DL" review-packet --devloop-dir "$TMP/dl" | grep -q 'review packet'; then
  ok 'review-packet via devloop'
else
  not_ok 'review-packet via devloop'
fi

if sh "$DL" not-a-cmd >/dev/null 2>&1; then
  not_ok 'unknown command fails'
else
  ok 'unknown command fails'
fi

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
