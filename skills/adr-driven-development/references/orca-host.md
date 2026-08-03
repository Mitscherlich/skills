# Orca host 执行手册（host=orca）

本文件是 `adr-driven-development` 在 **host 已定为 orca** 后的执行细节。契约（切片状态、DoD、跨工具验收、禁止内联实现）与主 SKILL 相同；此处只规定 **如何用 orca-cli 代替 tmux / 裸 git worktree**。

## 先决：host 由脚本决定，不在此文件里重探

进入 loop 时**只**跑：

```bash
<script-dir>/detect-runtime-host.sh          # 或 --force orca|tmux / --json
```

- 以输出的 `host=` / `orca_cli=` / `reason=` 为准。
- **`host` 不是 `orca` 时不要读本手册**（省 token）。
- 后续所有 `ORCA ...` 命令中的可执行名 = 脚本字段 `orca_cli`（可能是 `orca` / `orca-dev` / `orca-ide` / `ORCA_CLI_COMMAND` 的值）。
- 用户 `--host=` → `detect-runtime-host.sh --force <host>` 或环境变量 `ADR_HOST=`。

将脚本完整输出贴进 progress.md 启动行即可，例如：

```text
host=orca
orca_cli=orca
reason=orca env signals present and cli status ok
worktree_id=<repoId>::<absPath>   # create 后再补
impl_agent=claude
reviewer_agent=codex
```

命令面以本机 CLI 为准。host=orca 后首次操作前：

```text
ORCA skills get orca-cli
```

下文 `ORCA` 为占位符：替换为 `detect-runtime-host.sh` 给出的 `orca_cli`。**不要**在 Linux 非 Orca shell 里裸跑可能是读屏器的 `orca`（脚本在 Linux 非托管终端会优先 `orca-ide`）。

## agent id 映射（skill 名 → Orca）

| skill `--impl` / `--reviewer` | Orca `--agent` / terminal command | 说明 |
|---|---|---|
| `claude-code` | `claude` | Orca 侧 id 为 `claude`，不是 `claude-code` |
| `codex` | `codex` | |
| `grok` | `grok` | |

跨工具配对规则仍按主 SKILL：默认 reviewer ≠ impl。Orca 下同样禁止默认同 agent 自检。

## 一次 ADR 一个 Orca worktree（隔离执行区）

**impl 与 reviewer 必须共用同一 checkout**（否则验收看不到实现 commit）。不要为 reviewer 再 `worktree create` 一份平行树。

### 创建（loop 启动时一次）

在协调者所在 Orca worktree / 仓库上下文中：

```text
ORCA worktree create \
  --name adr-<id>-<slug> \
  --parent-worktree active \
  --json
```

要点：

- 需要挂在当前任务树下时用 `--parent-worktree active`；完全独立顶层任务才用 `--no-parent`。
- **不要**在 `worktree create` 上同时挂 `--agent` 做第一片实现——先落空 worktree（或仅 setup），再按切片扇出 terminal agent，便于一片一 handle、一报告。
- 若 CLI 较旧不支持某些 flag：先 `worktree create --name ... --json`，再用 `terminal create`。
- 从 create 响应抄写完整 `worktree.id`（格式 `<repoId>::<path>`），以及 path；写入 `.adr/<id>/progress.md` 与 plan 头注释。
- 在该 path 下创建 `.adr/<id>/`，后续所有绝对路径基于此 worktree path。
- 分支名尽量 `feat/adr<id>-<slug>`（Orca/checkout 若另有命名，以实际 branch 为准并记入 plan）。
- **绝不 push**。

可选状态：

```text
ORCA worktree set --worktree id:<repoId>::<path> --workspace-status in-progress --json
ORCA worktree set --worktree id:<repoId>::<path> --comment "ADR <id> loop: open F1" --json
```

### 已在目标 worktree 内

若协调者 cwd 已是目标 ADR worktree（`ORCA worktree current --json` 路径匹配），可复用，不再 create。

## 小周期 2：扇出 impl agent

goal 已写入 worktree 内绝对路径 `.../.adr/<id>/next-goal.md` 后：

### 推荐：在 ADR worktree 内新建 agent 终端

```text
ORCA terminal create \
  --worktree id:<repoId>::<adrWorktreePath> \
  --title adr-<slice>-impl \
  --command <impl_orca_agent> \
  --json
```

- `<impl_orca_agent>`：`claude` / `codex` / `grok`（映射表）。
- 从响应取 `handle`（或 `startupTerminal.handle`）；写入 progress：`impl_handle=...`。
- 若 handle 返回 `terminal_handle_stale`：`terminal list --worktree id:... --json` 重新获取，**只**对新 handle 操作。

等 TUI 就绪后投递任务（prompt 必须指向绝对路径，避免上下文丢失）：

```text
ORCA terminal wait --terminal <impl_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <impl_handle> --text "Read and execute the self-contained goal at <ABS>/.adr/<id>/next-goal.md. Work only in this worktree. Write the delivery report to <ABS>/.adr/<id>/run/<impl>-<slice>-report.md. Local commit only; never push. Do not advance plan.md roadmap status." --enter --json
```

若 goal 较短且 agent 支持 create 时 `--prompt`，也可在 **新切片专用子 worktree** 场景用 `worktree create --agent --prompt`；**本 skill 默认同一 ADR worktree + terminal create**，避免多 checkout 分叉。

### 完成判定（主会话 / 哨兵）

**文件哨兵优先**（与 host 无关）：

1. 存在 `.adr/<id>/run/<impl>-<slice>-report.md`
2. 有本片相关 commit（`git log` / `git status` 在 worktree path 内）
3. 可选：terminal 已 `tui-idle` 且近期无新输出

**不要**把「agent 口头说做完了」当完成。报告齐备 → 进入小周期 3。

### 日志

Orca TUI 无 stream-json tee 时：

- 用 `ORCA terminal read --terminal <impl_handle> --json`（必要时 cursor 翻页）摘最近动作，写入 progress 巡检行。
- 可把关键摘录追加到 `.adr/<id>/run/<impl>-<slice>.log`（人工/哨兵维护的摘要日志），便于与 tmux 路径产物对齐。

## 小周期 3：扇出 reviewer agent（不同工具）

impl 完成后，主会话写好 acceptance-prompt 绝对路径，再开 **另一条** terminal（**同一** ADR worktree）：

```text
ORCA terminal create \
  --worktree id:<repoId>::<adrWorktreePath> \
  --title adr-<slice>-review \
  --command <reviewer_orca_agent> \
  --json
ORCA terminal wait --terminal <review_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <review_handle> --text "You are the adversarial reviewer (impl=<impl>, reviewer=<reviewer>). Read <ABS>/.adr/<id>/run/<impl>-<slice>-acceptance-prompt.md and execute it. Write ONLY the acceptance report to <ABS>/.adr/<id>/run/<impl>-<slice>-acceptance.md with header impl=/reviewer=. Conclusion must be exactly one of: 全部完成 / 未完成 / BLOCKED. Do not change product code, do not commit, do not edit plan.md status." --enter --json
```

完成判定：acceptance 报告存在且结论三选一。然后主会话推进 roadmap。

card 状态建议：

- impl 进行中：`in-progress`
- reviewer 进行中：`in-review`
- 全片 done：`completed`（或最后一片再标）

```text
ORCA worktree set --worktree id:<repoId>::<path> --workspace-status in-review --json
ORCA worktree set --worktree id:<repoId>::<path> --comment "ADR <id> F2 acceptance running (reviewer=codex)" --json
```

## 哨兵（host=orca）

每 10 分钟：

1. `ORCA terminal list --worktree id:<...> --json` — impl/review handle 是否仍在
2. `ORCA terminal read --terminal <handle> --json`（或 cursor）— 最近动作摘要
3. worktree 内 `git log --oneline -3`、报告文件是否出现、roadmap open 片
4. 停滞：handle 仍在但输出/文件无进展 → 疑似停滞×N；连续 2 次通知用户
5. impl 报告已齐且仍 open → 启动 reviewer；acceptance 已齐 → 主会话核验结论

可用 Orca automations 做巡检，但默认仍用当前 agent 环境的定时任务机制，与 tmux 路径一致。

## 与 orchestration skill 的边界

- **本 skill 的 loop**：协调者监督「goal → impl terminal → reviewer terminal → 推进状态」，需要 wait/读报告，**不是** full handoff（交出后停摆）。
- 不要用 full handoff 把 loop 所有权扔给子 agent 后主会话退出。
- 若用户明确要求用 `orca orchestration` 做 DAG/多 worker 邮箱协调，另开 orchestration skill；默认 ADR loop 只用 `worktree` + `terminal` 子集，降低复杂度。

## 降级

| 情况 | 动作 |
|---|---|
| 探测到 Orca 但 `status` 失败 / CLI 缺失 | 记 progress，**降级 host=tmux**（或 paused 待用户装 Orca） |
| `worktree create` 失败 | 可回退 `git worktree add` + host=tmux；不得内联实现 |
| `terminal create --command` 不识别 agent | 查本机已装 agent；换配对或请用户安装 |
| 用户 `--host=tmux` | 全程走 launch-runner.sh + tmux，忽略 Orca 扇出 |

## 最小命令清单（备忘）

```text
ORCA status --json
ORCA worktree current --json
ORCA worktree create --name adr-<id>-<slug> --parent-worktree active --json
ORCA worktree set --worktree id:<repoId>::<path> --comment "..." --json
ORCA worktree set --worktree id:<repoId>::<path> --workspace-status in-progress --json
ORCA terminal create --worktree id:<repoId>::<path> --title adr-f1-impl --command claude --json
ORCA terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <handle> --text "..." --enter --json
ORCA terminal list --worktree id:<repoId>::<path> --json
ORCA terminal read --terminal <handle> --json
```

命令 flag 以 `ORCA skills get orca-cli` 为准；若与上文冲突，**以二进制指南为准**并更新本文件。
