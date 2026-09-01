# {{id}} · {{title}} · plan（loop 单一事实源）

> **阶段：plan（spec 编译产物）**。本文件是 loop 的**单一事实源**——哨兵与核验 agent 只认这里的切片状态列。
> 上游：`spec.md`
> spec_sha256: {{gate spec 通过时输出的 sha256}}
> 准出门禁：`devloop gate plan --file <本文件> --spec <spec.md>` 全绿 **且** 确认记录齐全，才能进入 loop。
> 执行区：worktree `{{绝对路径}}`（分支 `feat/devloop-{{id}}`）。host=`{{tmux|orca}}`。**绝不 push**。
> 每轮点火生成 attempt_id；产物路径含 attempt，或启动前把旧产物归档到 `run/archive/<attempt_id>/`。
> 切片状态词固定：`open`（当前在做，至多一个）/ `done (commit, 门禁数字)` / `pending` / `paused(原因)`。

## 背景与目标

{{一段话：从 spec 的「目标与验收终态」压缩而来，写清 loop 跑完时什么成立}}

## 需求追溯

> 证明 spec 的每条 `R<n>` 都被至少一个切片覆盖。门禁要求：至少一行 `R<n> → F<n>`；理想是每条 R 都在表内。

| 需求 | 覆盖切片 | 说明 |
|---|---|---|
| R1 | F1 | {{该切片如何满足 R1}} |

## 确认记录（进入 loop 前必填）

- 确认人：{{用户 / 责任人}}
- 确认时间：{{ISO 时间}}
- 确认范围：{{本 plan 覆盖哪些切片，哪些暂停}}
- 执行宿主（`--host`）：{{tmux|orca|自动探测}} —— **以 `devloop detect-host` 输出的 `host=` 为准**
  - 用户 `--host=` / `DEVLOOP_HOST=` 走严格 `--force`；仅偏好且允许降级时用 `--prefer`
- 哨兵调度：{{loop|orca-automation|cronjob}} —— **以 `devloop detect-scheduler` 为准**
- 协调者：{{claude-code|codex|grok|omp|…}}
- Orca setup policy：{{run|skip|inherit —— host=tmux 时写「不适用」}}
- 权限与 threat model：{{默认最小权限；若启用 bypassPermissions / danger sandbox，粘贴用户授权原文与必要性}}
- 实现 runner（`--impl`）：{{claude-code|codex|grok}}
- 对抗验收（`--reviewer`）：{{与 impl 不同的工具，或「按默认配对」}}
  - 默认配对：claude-code→codex/grok；codex→claude-code/grok；grok→claude-code/codex
- 同工具验收授权：{{无 —— 或粘贴用户明确授权原文及原因；「只剩一个工具」本身不构成授权}}
- source_worktree：{{grill 产出所在 checkout 绝对路径}}
- base_sha：{{执行 worktree 锁定的起点 SHA}}
- plan_sha256：{{迁移前后核对一致的 SHA-256}}
- control-plane 策略：{{`.devloop/` 随 feature 分支 commit（推荐）/ 外部归档；列出每片允许的 dirty path 与暂存 allowlist，禁止无边界 git add -A}}
- 进入 loop 结论：{{用户明确确认的原文或摘要}}

## 切片 roadmap

| # | 切片 | 状态 | 范围（引用 R / I 编号） | DoD 附加项 |
|---|---|---|---|---|
| F1 | {{名}} | open | {{R1、R2：做什么}} | {{该片特有验收点}} |
| F2 | {{名}} | pending | {{R3：做什么}} | {{…}} |
| F9 | {{需人工输入的片}} | paused(需凭据) | **PAUSE 点**：{{需要用户提供什么}} | 到达即通知用户 |

## 每片统一 DoD（写进每份 goal）

1. 范围内新逻辑有测试；全仓门禁 {{lint/typecheck/test 命令}} 全绿。
2. 本地 commit（message 前缀 `feat({{id}}-<slice>):`），**绝不 push**。
3. impl runner 报告写 `.devloop/{{id}}/run/<impl>-<slice>-report.md`：`attempt_id`、`goal_sha256`、`base_sha`、`head_sha`、变更清单、门禁数字、设计取舍、计划偏差；先写同目录临时文件，完整落盘后 atomic rename。
4. reviewer 写 `.devloop/{{id}}/run/<impl>-<slice>-acceptance.md`（注明 impl/reviewer 及同一组 attempt/hash，记录 reviewed `head_sha`），结论为 `全部完成` 且当前 HEAD 未漂移才能推进下一片。
5. 遇下列情况**停止并在报告写明 BLOCKED**：语义歧义无法自决 / 门禁 3 轮修复不过 / 需要外部凭据。

## loop 小周期协议

1. 检查确认记录齐全且当前恰好一个 `open` 片；否则回到 plan 编译或暂停。
2. 执行 `.devloop` lifecycle 交接：从 `source_worktree` 用 `cp -a` / `rsync` 迁入执行区并核对 `plan_sha256`；依赖 dirty 业务改动时暂停，让用户选择先 commit / patch 导入 / 改用当前 checkout。执行区设置 `git config remote.origin.pushurl no_push`。
3. 解析 host：执行 `devloop detect-host`（用户指定加 `--force`，仅偏好加 `--prefer`），采用 stdout 的 `host=` / `orca_cli=`；勿手推。`--force tmux` 不得调用 Orca。
4. 解析哨兵调度：执行 `devloop detect-scheduler`。`loop` 用 `/loop`；`orca-automation` 自动建 Orca automation 并告知用户；`ask` 才停下来让用户选。未选不得点火。
5. re-open 或重新点火前，先把旧 report/acceptance 归档到 `run/archive/<旧 attempt_id>/`；生成新 `attempt_id`，再按 `templates/next-goal.md` 编译 next-goal.md。编译子代理只写 goal，不改代码。
6. 按 host 点火 **impl**（tmux session / Orca terminal 命名 `devloop-{{id}}-<slice>`）。每 tick 用 `devloop lock acquire` 抢阶段锁；哨兵按 attempt/hash/mtime/HEAD 核验，不得只看固定路径存在。host=orca 时每 tick 跑 `devloop cleanup-sessions`。主会话不得内联实现业务代码。
7. impl 完成后冻结 impl，记录待验 HEAD，写 acceptance-prompt；启动**与 impl 不同的 reviewer**（同一 worktree）。同工具验收须用户明确授权。reviewer 只写 acceptance / 只读复跑门禁；acceptance 外新增 diff 即 `BLOCKED`。
8. acceptance 合法且当前 HEAD 等于 reviewed `head_sha`、结论 `全部完成` → 本片置 `done (commit, 数字)`；有 pending 片则下一片置 `open`。
9. 结论 `未完成` → 保持 `open`，归档本轮产物后编译修复 goal；`BLOCKED` → 置 `paused(原因)` 并通知用户。
10. 全部 `done` → 最终汇总、删哨兵、host=orca 再清一次 session、按 control-plane 策略提交 / 归档 `.devloop/`；确认归档并获用户授权后才允许 `worktree rm`。
