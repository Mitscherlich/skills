# Control-plane kernel 契约（0.6.x）

协调 agent **优先调用** `scripts/devloop` 子命令，而不是重读全部 SKILL 规程来推断下一步。

## 入口

```bash
<path-to-skill>/scripts/devloop <command> [args]
# 或
sh <path-to-skill>/scripts/devloop <command> [args]
```

版本：`devloop version` → `0.6.0`

## 子命令

| 命令 | 作用 | 关键退出码 |
|------|------|------------|
| `init --id ID [--title T] [--root DIR] [--stage S] [--force]` | 从 `templates/` 落盘控制面目录 | 0 写入 / 1 已存在未覆盖 |
| `gate intent --file PATH` | intent 准出门禁（含人工审阅签字校验） | 0 通过 / 1 未通过 |
| `gate spec --file PATH [--intent PATH]` | spec 准出门禁（含过程性残留、sha 绑定） | 0 / 1 |
| `gate plan --file PATH [--spec PATH]` | plan 准出门禁（含需求追溯、唯一 open） | 0 / 1 |
| `gate goal --file PATH [--spec PATH] [--plan PATH]` | next-goal 准出门禁（七字段、header 齐全、GOAL_SHA256 自校验） | 0 / 1 |
| `stage validate\|can\|transitions --from S [--to S]` | 管线阶段跃迁合法性 | can: 0 允许 / 1 拒绝 |
| `doctor` | 检查 skill 布局、脚本语法、tmux/git | 0 健康 / 1 失败 |
| `detect-host [...]` | 包装 `detect-runtime-host.sh` | 同原脚本 |
| `detect-scheduler [...]` | `/loop` → Orca automation → ask | 0 已决定 / 1 必须问用户 |
| `cleanup-sessions --orca-cli C --worktree ID` | 关闭 worktree 里已完成的 Orca session | 0 |
| `attempt new [--prefix P]` | 生成不可复用 attempt_id | 0 + stdout id |
| `attempt archive --run-dir D --attempt-id ID` | 归档 report/acceptance 到 `run/archive/<id>/` | 0 |
| `lock acquire\|release\|check --run-dir D --phase P` | 原子 mkdir 锁（compile\|impl\|review\|advance） | 0 获得 / 1 忙 |
| `state validate\|can\|transitions` | **切片**状态转移合法性 | can: 0 允许 / 1 拒绝 |
| `status --plan PATH [--json]` | 解析 roadmap 表 | 多 open → 1 |
| `next --dir DIR` | **全管线**下一步（先跑三道门禁） | 0 |
| `next --plan PATH [--run-dir D]` | 仅切片层下一步 | 0 |
| `review-packet --devloop-dir PATH` | 人类可读压缩摘要（含 Pipeline 门禁表） | 0 |
| `run-tests` | 跑 `tests/*.test.sh`（装机自检：验证 sed/awk/bash/sha 在本机行为符合预期） | 0 全绿 / 1 有失败 / 2 没找到测试 |

## 两套状态机

**管线阶段**（`devloop stage`）：

```
intent → spec → plan → loop → done
```

打回边：`spec → intent`、`plan → spec`、`loop → plan`、`done → loop`。**不允许跳级**（`intent → plan` 被拒）。

**切片状态**（`devloop state`）：

```
pending → open → implementing → reviewing → done
```

旁路：`open|implementing|reviewing → paused`；`paused → open`；`done → open`（re-open）。
plan.md 表内 `done (...)` / `paused(...)` 会归一化为 `done` / `paused`。

## 与流程的映射

| 阶段 | kernel 用法 |
|--------|-------------|
| 启动 | `devloop doctor`；`devloop init --id <id>` |
| grill 中 / 结束 | `devloop gate intent --file .devloop/<id>/intent.md` |
| 编译 spec 后 | `devloop gate spec --file … --intent …` |
| 编译 plan 后 | `devloop gate plan --file … --spec …` |
| 编译 goal 后 | `devloop gate goal --file … --spec … --plan …` |
| 进入 loop | `devloop detect-host`；`devloop detect-scheduler` |
| 点火前 | `devloop attempt new`；必要时 `devloop attempt archive` |
| 哨兵 tick | `devloop lock acquire --phase …`；`devloop next --dir …`；host=orca 时 `devloop cleanup-sessions` |
| 推进 | `devloop state can --from reviewing --to done` |
| 汇报人类 | `devloop review-packet --devloop-dir .devloop/<id>` |

## 非目标（0.6.x）

- 不负责 spawn agent / tmux session（仍用 launch-runner / Orca 文档）
- 无跨会话 daemon（0.7.x `tick`/`watch`）
- 门禁只做**结构与绑定**校验，不做语义评审——语义由人工审阅 / 签署 / 确认三道人的门禁把关
