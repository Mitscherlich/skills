# Control-plane kernel 契约（0.5.x）

协调 agent **优先调用** `scripts/adr` 子命令，而不是重读全部 SKILL 规程来推断下一步。

## 入口

```bash
<path-to-skill>/scripts/adr <command> [args]
# 或
sh <path-to-skill>/scripts/adr <command> [args]
```

版本：`adr version` → `0.5.1`

## 子命令

| 命令 | 作用 | 关键退出码 |
|------|------|------------|
| `doctor` | 检查 skill 布局、脚本语法、tmux/git | 0 健康 / 1 失败 |
| `detect-host [...]` | 包装 `detect-runtime-host.sh` | 同原脚本 |
| `detect-scheduler [...]` | 包装 `detect-loop-scheduler.sh`（`/loop` → Orca automation → ask） | 0 已决定 / 1 必须问用户 / 2 参数错 |
| `cleanup-sessions --orca-cli C --worktree ID` | 关闭 ADR worktree 里已完成的 Orca session | 0 |
| `attempt new [--prefix P]` | 生成不可复用 attempt_id | 0 + stdout id |
| `attempt archive --run-dir D --attempt-id ID` | 归档 report/acceptance 到 `run/archive/<id>/` | 0 |
| `lock acquire --run-dir D --phase P` | 原子 mkdir 锁（compile\|impl\|review\|advance） | 0 获得 / 1 忙 |
| `lock release --run-dir D --phase P` | 释放锁 | 0 |
| `lock check --run-dir D --phase P` | 是否持有 | 0 held / 1 free |
| `state validate\|can\|transitions` | 切片状态转移合法性 | can: 0 允许 / 1 拒绝 |
| `status --plan PATH [--json]` | 解析 roadmap 表 | 多 open → 1 |
| `next --plan PATH [--run-dir D]` | 下一步动作（work_open_slice / finalize / …） | 0 |
| `review-packet --adr-dir PATH` | 人类可读压缩摘要 | 0 |

## 状态机（canonical）

`pending → open → implementing → reviewing → done`  
旁路：`open|implementing|reviewing → paused`；`paused → open`；`done → open`（re-open）。

plan.md 表内 `done (...)` / `paused(...)` 会归一化为 `done` / `paused`。

## 与 loop 的映射

| 小周期 | kernel 用法 |
|--------|-------------|
| 进入 loop | `adr doctor`；`adr detect-host`；`adr detect-scheduler` |
| 点火前 | `adr attempt new`；必要时 `adr attempt archive` |
| 哨兵 tick | `adr lock acquire --phase …`；`adr status`；`adr next`；host=orca 时 `adr cleanup-sessions` |
| 推进 | `adr state can --from reviewing --to done` |
| 汇报人类 | `adr review-packet --adr-dir .adr/<id>` |

## 非目标（0.5.x）

- 不负责 spawn agent / tmux session（仍用 launch-runner / Orca 文档）
- 无跨会话 daemon（0.6.x `tick`/`watch`）
- 无 typed human gate 存储（0.6.x）
