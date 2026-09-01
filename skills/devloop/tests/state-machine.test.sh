#!/usr/bin/env sh
set -u

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SM="$TEST_DIR/../scripts/state-machine.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf 'ok %s - %s\n' "$PASS" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %s - %s\n' "$((PASS + FAIL))" "$1" >&2; }

if sh -n "$SM"; then ok 'sh -n state-machine.sh'; else not_ok 'sh -n state-machine.sh'; fi

if sh "$SM" can --from open --to implementing; then ok 'open->implementing'; else not_ok 'open->implementing'; fi
if sh "$SM" can --from implementing --to reviewing; then ok 'implementing->reviewing'; else not_ok 'implementing->reviewing'; fi
if sh "$SM" can --from reviewing --to done; then ok 'reviewing->done'; else not_ok 'reviewing->done'; fi
if sh "$SM" can --from pending --to open; then ok 'pending->open'; else not_ok 'pending->open'; fi
if sh "$SM" can --from done --to open; then ok 're-open allowed'; else not_ok 're-open allowed'; fi

if sh "$SM" can --from pending --to done 2>/dev/null; then
  not_ok 'pending->done illegal'
else
  ok 'pending->done illegal'
fi

if sh "$SM" can --from done --to reviewing 2>/dev/null; then
  not_ok 'done->reviewing illegal'
else
  ok 'done->reviewing illegal'
fi

# normalize done (commit, 3)
if sh "$SM" validate --from reviewing --to 'done (abc, 1)' >/dev/null; then
  ok 'normalize done(...)'
else
  not_ok 'normalize done(...)'
fi

out=$(sh "$SM" transitions --from open)
echo "$out" | grep -qx implementing && ok 'transitions lists implementing' || not_ok 'transitions lists implementing'


# ── 管线阶段轴 ────────────────────────────────────────────────
sm_can() { sh "$SM" stage-can --from "$1" --to "$2"; }

sm_can intent spec && ok 'stage intent->spec' || not_ok 'stage intent->spec'
sm_can spec plan && ok 'stage spec->plan' || not_ok 'stage spec->plan'
sm_can plan loop && ok 'stage plan->loop' || not_ok 'stage plan->loop'
sm_can loop done && ok 'stage loop->done' || not_ok 'stage loop->done'
sm_can spec intent && ok 'stage spec->intent 打回' || not_ok 'stage spec->intent 打回'
sm_can plan spec && ok 'stage plan->spec 打回' || not_ok 'stage plan->spec 打回'
sm_can loop plan && ok 'stage loop->plan 重规划' || not_ok 'stage loop->plan 重规划'
sm_can done loop && ok 'stage done->loop re-open' || not_ok 'stage done->loop re-open'

sm_can intent plan && not_ok 'stage 拒绝 intent->plan 跳级' || ok 'stage 拒绝 intent->plan 跳级'
sm_can intent loop && not_ok 'stage 拒绝 intent->loop 跳级' || ok 'stage 拒绝 intent->loop 跳级'
sm_can spec loop && not_ok 'stage 拒绝 spec->loop 跳级' || ok 'stage 拒绝 spec->loop 跳级'
sm_can done intent && not_ok 'stage 拒绝 done->intent' || ok 'stage 拒绝 done->intent'

out=$(sh "$SM" stage-validate --from intent --to spec)
echo "$out" | grep -qx 'kind=stage' && ok 'stage-validate 标注 kind' || not_ok 'stage-validate 标注 kind'

tr_out=$(sh "$SM" stage-transitions --from plan)
echo "$tr_out" | grep -qx 'loop' && ok 'stage-transitions 列出 loop' || not_ok 'stage-transitions 列出 loop'
echo "$tr_out" | grep -qx 'spec' && ok 'stage-transitions 列出 spec' || not_ok 'stage-transitions 列出 spec'

# 两套状态机互不串味
sm_can open spec && not_ok '切片状态与阶段不串' || ok '切片状态与阶段不串'

TOTAL=$((PASS + FAIL))
printf '1..%s\n' "$TOTAL"
[ "$FAIL" -eq 0 ] || exit 1
printf '%s test(s) passed\n' "$PASS"
