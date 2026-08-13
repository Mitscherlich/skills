# Orca host 执行手册（host=orca）

本文件是 `devloop` 在 **host 已定为 orca** 后的执行细节。契约（切片状态、DoD、跨工具验收、禁止内联实现）与主 SKILL 相同；此处只规定 **如何用 orca-cli 代替 tmux / 裸 git worktree**。

## 先决：host 由脚本决定，不在此文件里重探

进入 loop 时**只**跑：

```bash
<script-dir>/detect-runtime-host.sh          # 或 --force orca|tmux / --json
```

- 以输出的 `host=` / `orca_cli=` / `reason=` 为准。
- **`host` 不是 `orca` 时不要读本手册**（省 token）。
- 后续所有 `ORCA ...` 命令中的可执行名 = 脚本字段 `orca_cli`（可能是 `orca` / `orca-dev` / `orca-ide` / `ORCA_CLI_COMMAND` 的值）。
- 用户 `--host=` / `ADR_HOST=` → `detect-runtime-host.sh --force <host>`，这是严格选择，不可用即失败；仅偏好且允许降级时用 `--prefer <host>`。
- `--force tmux` 必须完全不调用 Orca；自动探测或 `--prefer` 失败降级才是 prefer 语义。

将脚本完整输出贴进 progress.md 启动行即可，例如：

```text
host=orca
orca_cli=orca
reason=orca env signals present and cli status ok
worktree_id=<repoId>::<absPath>   # create 后再补
setup=inherit                       # run|skip|inherit，按 plan
base_sha=<lockedBaseSha>
plan_sha256=<verifiedPlanHash>
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

跨工具配对规则仍按主 SKILL：默认 reviewer ≠ impl。Orca 下同样禁止默认同 agent 自检；任何同工具验收都须先取得用户明确授权并记入 plan/progress，「只剩一个工具」只触发询问。

权限默认最小化。plan 必须记录 impl/reviewer 的命令与 threat model；例如 Claude 默认 `claude --permission-mode default`，只有用户已授权才可写成 `claude --permission-mode bypassPermissions`。Codex 使用 `codex --sandbox workspace-write`；danger sandbox 或同类 bypass 也只在 plan 有明确授权时启用。

## 一次 ADR 一个 Orca worktree（隔离执行区）

**impl 与 reviewer 必须共用同一 checkout**（否则验收看不到实现 commit）。不要为 reviewer 再 `worktree create` 一份平行树。

### 创建（loop 启动时一次）

在协调者所在 Orca worktree / 仓库上下文中：

```text
ORCA worktree create \
  --name adr-<id>-<slug> \
  --parent-worktree active \
  --setup <run|skip|inherit> \
  --json
```

要点：

- 需要挂在当前任务树下时用 `--parent-worktree active`；完全独立顶层任务才用 `--no-parent`。
- setup policy 必须先在 plan 记录为 `setup=run|skip|inherit`，再显式传 `--setup`；不要让仓库默认 setup 成为未审计副作用。
- 若 F1 goal 已就绪，可用 `worktree create --agent <impl> --prompt <goal>` 一次性创建执行区并点火，但必须仍保持“一 ADR 一 worktree”、后续 reviewer/F2 复用同一 ADR worktree 的语义；goal 未就绪时先 bare create，再 `terminal create`。
- 若 CLI 较旧不支持某些 flag：先 `worktree create --name ... --json`，再用 `terminal create`。
- 从 create 响应抄写完整 `worktree.id`（格式 `<repoId>::<path>`），以及 path；写入 `.adr/<id>/progress.md` 与 plan 头注释。
- 创建后从 `source_worktree` 用 `cp -a` 或 `rsync` 迁入 `.adr/<id>/`，核对 plan 记录的 `plan_sha256`；执行区必须从锁定的 `base_sha` 起步。
- 若实现依赖 source checkout 的 dirty 业务改动，暂停让用户选择先 commit / patch 导入 / 改用当前 checkout，禁止静默丢失。
- 在执行区运行 `git config remote.origin.pushurl no_push`（或等价硬禁 push）并验证；后续所有绝对路径基于该 worktree path。
- 分支名尽量 `feat/adr<id>-<slug>`（Orca/checkout 若另有命名，以实际 branch 为准并记入 plan）。
- `.adr/` 的 commit/归档与 dirty allowlist 以 plan 的 control-plane 策略为准；impl 避免无边界 `git add -A`。**绝不 push**。

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
  --title adr-<id>-<slice>-impl-<attempt> \
  --command "<impl_agent_with_plan_authorized_permission_flags>" \
  --json
```

- `<impl_orca_agent>`：`claude` / `codex` / `grok`（映射表）。
- 从 create 响应优先取 `agentTerminalHandle`，兼容旧版 `startupTerminal.handle`；写入 progress：`impl_handle=...`。
- 若返回 `terminal_handle_stale`，先 `terminal list --worktree id:... --json`，再按 worktree id、完整 title、command/agent 与当前 attempt 四项重绑；**只**对新 handle 操作，禁止双发。
- 故障恢复先核对 title/handle，再用 `ORCA terminal close --terminal <handle>` 精确关闭并重建；**禁止**默认使用会停止整个 worktree 的 `terminal stop --worktree`。

等 TUI 就绪后投递任务（prompt 必须指向绝对路径，避免上下文丢失）：

```text
ORCA terminal wait --terminal <impl_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <impl_handle> --text "Read and execute the self-contained goal at <ABS>/.adr/<id>/next-goal.md. Work only in this worktree. Write the delivery report to <ABS>/.adr/<id>/run/<impl>-<slice>-report.md. Local commit only; never push. Do not advance plan.md roadmap status." --enter --json
```

F1 在 goal 已就绪时可用 `worktree create --agent <impl> --prompt <ABS-goal>` 点火；该 create 得到的 worktree 就是本 ADR 唯一执行区，后续 reviewer/F2 必须复用它，不得再建“新切片专用子 worktree”。goal 尚未就绪或复用既有 ADR worktree 时，使用 `terminal create`。

### 完成判定（主会话 / 哨兵）

**attempt 哨兵优先**（与 host 无关），不得只检查固定路径存在：

1. report 的 `attempt_id`、`goal_sha256`、`base_sha` 与当前 goal 一致，`head_sha` 对应本片 commit。
2. report mtime 晚于本轮 goal 写入与 archive 动作；re-open 前旧 report/acceptance 已归档到 `run/archive/<attempt_id>/`，或产物路径本身含 attempt。
3. terminal 已 `tui-idle` / 退出并冻结，当前 HEAD 等于 report 的 `head_sha`。

报告先写临时文件后 atomic rename。**不要**把 agent 口头完成或旧固定路径文件当完成；全部绑定通过才进入小周期 3。

### 日志

Orca TUI 无 stream-json tee 时：

- 用 `ORCA terminal read --terminal <impl_handle> --json`（必要时 cursor 翻页）摘最近动作，写入 progress 巡检行。
- 可把关键摘录追加到 `.adr/<id>/run/<impl>-<slice>.log`（人工/哨兵维护的摘要日志），便于与 tmux 路径产物对齐。

## 小周期 3：扇出 reviewer agent（不同工具）

impl 完成后，主会话写好 acceptance-prompt 绝对路径，再开 **另一条** terminal（**同一** ADR worktree）：

```text
ORCA terminal create \
  --worktree id:<repoId>::<adrWorktreePath> \
  --title adr-<id>-<slice>-review-<attempt> \
  --command "<reviewer_agent_with_plan_authorized_permission_flags>" \
  --json
ORCA terminal wait --terminal <review_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <review_handle> --text "You are the adversarial reviewer (impl=<impl>, reviewer=<reviewer>). Read <ABS>/.adr/<id>/run/<impl>-<slice>-acceptance-prompt.md and execute it. Write ONLY the acceptance report to <ABS>/.adr/<id>/run/<impl>-<slice>-acceptance.md with header impl=/reviewer=. Conclusion must be exactly one of: 全部完成 / 未完成 / BLOCKED. Do not change product code, do not commit, do not edit plan.md status." --enter --json
```

reviewer 只写 acceptance（及只读复跑测试），不改业务代码、commit 或 plan 状态。review 前后比较 diff；acceptance allowlist 外出现新增 diff 即 `BLOCKED`。acceptance 先写临时文件后 atomic rename；只有其 `attempt_id` / `goal_sha256` / `base_sha` / reviewed `head_sha` / mtime 与当前轮匹配，且当前 HEAD 等于 reviewed head，才允许主会话推进 roadmap。

card 状态建议：

- impl 进行中：`in-progress`
- reviewer 进行中：`in-review`
- 全片 done：`completed`（或最后一片再标）

```text
ORCA worktree set --worktree id:<repoId>::<path> --workspace-status in-review --json
ORCA worktree set --worktree id:<repoId>::<path> --comment "ADR <id> F2 acceptance running (reviewer=codex)" --json
```

## 哨兵（host=orca）

每 10 分钟先用原子 `mkdir .adr/<id>/run/.lock-<phase>` 抢占 `compile|impl|review|advance` 锁；未抢到立即退出，锁拥有者完成后释放，避免两个 tick 重复扇出。然后：

1. `ORCA terminal list --worktree id:<...> --json` — impl/review handle 是否仍在
2. `ORCA terminal read --terminal <handle> --json`（或 cursor）— 最近动作摘要
3. worktree 内 `git log --oneline -3`、当前 attempt 的 report/acceptance 绑定与 mtime、roadmap open 片
4. 停滞：handle 仍在但输出/文件无进展 → 疑似停滞×N；连续 2 次通知用户
5. impl 报告绑定齐且仍 open → 启动 reviewer；acceptance 绑定齐且 HEAD 等于 reviewed head → 主会话核验结论

默认定时机制多为会话级，协调者退出即 loop 停止。长 loop 应使用 Orca automations（或明确的持久调度器），并沿用同一 attempt/锁协议。

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
| 单 terminal 卡死 / handle stale | 核对 worktree+title+attempt 后 `terminal close --terminal <handle>`，重建并生成新 attempt；禁止默认 `terminal stop --worktree` |
| 用户 `--host=tmux` | 全程走 launch-runner.sh + tmux，忽略 Orca 扇出 |

## 最小命令清单（备忘）

```text
ORCA status --json
ORCA worktree current --json
ORCA worktree create --name adr-<id>-<slug> --parent-worktree active --setup <policy> --json
ORCA worktree set --worktree id:<repoId>::<path> --comment "..." --json
ORCA worktree set --worktree id:<repoId>::<path> --workspace-status in-progress --json
ORCA terminal create --worktree id:<repoId>::<path> --title adr-<id>-f1-impl-<attempt> --command "claude --permission-mode default" --json
ORCA terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <handle> --text "..." --enter --json
ORCA terminal list --worktree id:<repoId>::<path> --json
ORCA terminal read --terminal <handle> --json
ORCA terminal close --terminal <handle> --json
```

命令 flag 以 `ORCA skills get orca-cli` 为准；若与上文冲突，**以二进制指南为准**并更新本文件。
