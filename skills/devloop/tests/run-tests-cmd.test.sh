#!/usr/bin/env sh
set -u
TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DL="$TEST_DIR/../scripts/devloop"
RT="$TEST_DIR/../scripts/run-tests.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$RT"; then ok 'sh -n run-tests.sh'; else not_ok 'sh -n run-tests.sh'; fi
if sh -n "$DL"; then ok 'sh -n devloop'; else not_ok 'sh -n devloop'; fi

help=$(sh "$DL" help 2>&1)
echo "$help" | grep -q 'run-tests' && ok 'help lists run-tests' || not_ok 'help lists run-tests'

# Do not invoke full suite here (would recurse when run-tests runs this file).
# Smoke: script header documents exit semantics.
grep -q 'exit non-zero' "$RT" && ok 'run-tests documents failure semantics' || not_ok 'run-tests documents failure semantics'

# 退出码契约：在隔离的假 skill 根上验，避免递归跑自己
TMP=$(mktemp -d "${TMPDIR:-/tmp}/devloop-rt.test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

mk_root() {  # mk_root <name> —— 造一个只含 scripts/run-tests.sh 的假 skill 根
  mkdir -p "$TMP/$1/scripts"
  cp "$RT" "$TMP/$1/scripts/run-tests.sh"
  printf '%s' "$TMP/$1/scripts/run-tests.sh"
}
run_code() { sh "$1" >/dev/null 2>&1; printf '%s' "$?"; }

# tests/ 不存在 → 必须报错退 2，绝不能假报 files_passed=0 然后退 0
R=$(mk_root nodir)
code=$(run_code "$R")
[ "$code" = 2 ] && ok 'tests/ 缺失时退 2（不假绿）' || not_ok "tests/ 缺失时退 2（got $code）"
sh "$R" 2>&1 | grep -q 'no tests found' && ok '缺失时打印 no tests found' || not_ok '缺失时打印 no tests found'

# tests/ 存在但没有 .test.sh → 同样是「一个都没跑」
R=$(mk_root emptydir); mkdir -p "$TMP/emptydir/tests"
code=$(run_code "$R")
[ "$code" = 2 ] && ok '空 tests/ 退 2' || not_ok "空 tests/ 退 2（got $code）"

# 有测试且全绿 → 0
R=$(mk_root green); mkdir -p "$TMP/green/tests"
printf '#!/usr/bin/env sh\nexit 0\n' >"$TMP/green/tests/a.test.sh"
code=$(run_code "$R")
[ "$code" = 0 ] && ok '全绿退 0' || not_ok "全绿退 0（got $code）"

# 有测试且失败 → 1（与「没跑起来」的 2 区分）
R=$(mk_root red); mkdir -p "$TMP/red/tests"
printf '#!/usr/bin/env sh\nexit 1\n' >"$TMP/red/tests/a.test.sh"
code=$(run_code "$R")
[ "$code" = 1 ] && ok '测试失败退 1（不是 2）' || not_ok "测试失败退 1（got $code）"

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
