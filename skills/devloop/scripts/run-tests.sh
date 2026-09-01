#!/usr/bin/env sh
# run-tests.sh — run all skill tests; exit non-zero on first failure
# exit: 0 全绿 / 1 有测试文件失败 / 2 一个测试文件都没找到
#       （2 与 gate.sh 同口径：区分「跑了没过」和「根本没跑起来」——
#        tests/ 缺失时静默 files_passed=0 退 0 就是自报完成，本 skill 明令禁止）
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FAIL=0
PASS_FILES=0
FOUND=0
for t in "$ROOT"/tests/*.test.sh; do
  [ -f "$t" ] || continue
  FOUND=$((FOUND + 1))
  if sh "$t"; then
    PASS_FILES=$((PASS_FILES + 1))
  else
    printf 'FAIL %s\n' "$t" >&2
    FAIL=1
  fi
done
if [ "$FOUND" -eq 0 ]; then
  printf 'error: no tests found under %s/tests\n' "$ROOT" >&2
  exit 2
fi

printf 'files_passed=%s\n' "$PASS_FILES"
[ "$FAIL" -eq 0 ]
