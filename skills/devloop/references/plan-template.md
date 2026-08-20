# plan.md 模板（.adr/<id>/plan.md）

grill 阶段边聊边填「决策」小节；grill 收尾时补「切片 roadmap」并取得用户确认。此文件是 loop 的**单一事实源**：哨兵与核验 agent 只认这里的状态列。没有「确认记录」不得进入 loop 或启动 host runner。

```markdown
# ADR <id> <标题> · plan（loop 单一事实源）

> 执行区：worktree `<path>`（分支 `feat/adr<id>-<slug>`）。host=`<tmux|orca>`。**绝不 push**。
> host=orca 时记录 Orca worktree id：`<repoId>::<path>`。
> source_worktree=`<grill checkout>`；base_sha=`<执行区起点>`；plan_sha256=`<已确认 plan hash>`。
> 每轮点火生成 attempt_id；产物路径含 attempt，或启动前归档旧产物到 `run/archive/<attempt_id>/`。
> 每片本地 commit + impl 报告落 `.adr/<id>/run/<impl>-<slice>-report.md`。
> 每片验收 prompt 落 `.adr/<id>/run/<impl>-<slice>-acceptance-prompt.md`；验收报告落 `.adr/<id>/run/<impl>-<slice>-acceptance.md`（由 **reviewer** 写，均绑定 attempt/hash）。
> 状态：`open`（当前在做，至多一个）/ `done` / `pending` / `paused(原因)`。

## 背景与目标

<一段话：要解决什么问题，验收终态是什么>

## 决策（grill 产出，边聊边追加）

1. **<决策点>**：<裁决结果 + 一句话理由>
2. ...

## 确认记录（进入 loop 前必填）

- 确认人：<用户/责任人>
- 确认时间：<ISO 时间>
- 确认范围：<本 plan 覆盖哪些切片，哪些暂停>
- 执行宿主（`--host`）：`<tmux|orca|自动>` — **以 `scripts/detect-runtime-host.sh` 输出的 host= 为准**
  - 自动探测勿手推；用户 `--host=` / `ADR_HOST=` 使用严格 `--force`，仅偏好且允许降级时用 `--prefer`
- 哨兵调度：`</loop|orca-automation|cronjob|待选>` — **以 `scripts/detect-loop-scheduler.sh` 为准**；有 `/loop` 用 `/loop`；无 `/loop` 且在 Orca 则自动 automation 并告知；其余才问用户
- 协调者：`<claude-code|codex|grok|omp|…>`
- Orca setup policy：`setup=<run|skip|inherit>`（host=tmux 时填不适用）
- 权限与 threat model：<默认最小权限；若使用 bypassPermissions / danger sandbox，粘贴用户授权及必要性>
- 实现 runner（`--impl`）：`<claude-code|codex|grok>`（Orca agent：`claude`/`codex`/`grok`）
- 对抗验收（`--reviewer`）：`<与 impl 不同的工具，或「按默认配对」>`  
  - 默认配对：claude-code→codex/grok；codex→claude-code/grok；grok→claude-code/codex
- 同工具验收授权：<无 / 用户明确授权原文及原因；只剩一个工具本身不构成授权>
- grilling 依赖：<已装 mattpocock/skills / 用户拒绝安装并选用现成设计|轻量访谈>
- source_worktree：`<grill 产出所在 checkout 绝对路径>`
- base_sha：`<执行 worktree 锁定的起点 SHA>`
- plan_sha256：`<迁移前后核对一致的 SHA-256>`
- control-plane 策略：<`.adr/` 随 feature 分支 commit（推荐）/ 外部归档；列出每片允许的 dirty path 与暂存 allowlist，禁止无边界 `git add -A`>
- 进入 loop 结论：<用户明确确认原文或摘要>

## 切片 roadmap

| # | 切片 | 状态 | 范围（引用上面决策号） | DoD 附加项 |
|---|---|---|---|---|
| F1 | <名> | open | 决策 1/2：<做什么> | <该片特有验收点> |
| F2 | <名> | pending | 决策 3：<做什么> | ... |
| FN | <需人工输入的片> | paused(需凭据) | **PAUSE 点**：<需要用户提供什么> | 到达即通知用户 |

## 每片统一 DoD（写进每份 goal）

1. 范围内新逻辑有测试；全仓门禁 `<lint/typecheck/test 命令>` 全绿。
2. 本地 commit（message 前缀 `feat(adr<id>-<slice>):`），**绝不 push**。
3. impl runner 报告写 `.adr/<id>/run/<impl>-<slice>-report.md`：`attempt_id`、`goal_sha256`、`base_sha`、`head_sha`、变更清单、门禁数字、设计取舍、发现的计划偏差；同目录临时文件写完后 atomic rename。
4. reviewer 写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`（注明 impl/reviewer 及同一 attempt/hash，记录 reviewed `head_sha`），结论为 `全部完成` 且当前 HEAD 未漂移才能推进下一片。
5. 遇下列情况**停止并在报告写明 BLOCKED**：语义歧义无法自决 / 门禁 3 轮修复不过 / 需要外部凭据。

## loop 小周期协议

1. 检查确认记录存在且当前只有一个 `open` 片；否则回到 grill 或暂停。确认记录须含 host / impl / reviewer（或「自动探测」「按默认配对」）。
2. 执行 `.adr` lifecycle 交接：从 `source_worktree` 用 `cp -a` / `rsync` 迁入执行区并核对 `plan_sha256`；依赖 dirty 业务改动时暂停，让用户选择先 commit / patch 导入 / 改用当前 checkout。执行区设置 `git config remote.origin.pushurl no_push` 或等价硬禁 push。
3. 解析 host：**执行** `scripts/detect-runtime-host.sh`（用户指定则加严格 `--force`，偏好才加 `--prefer`），采用 stdout 的 `host=` / `orca_cli=`；勿手推。`--force tmux` 不得调用 Orca。host=orca 时再读 `references/orca-host.md` 做 worktree/terminal 扇出。
4. 解析哨兵调度：**执行** `scripts/detect-loop-scheduler.sh`。`loop` 用 `/loop`；`orca-automation` 自动建 Orca automation 并告知用户；`ask` 才停下来让用户选 cronjob 或换协调者。未选不得点火。
5. re-open 切片或重新点火前，先把旧 report/acceptance 归档到 `run/archive/<旧 attempt_id>/`（或改用含 attempt 的新路径）；生成新 `attempt_id`，再按 `references/goal-template.md` 写 next-goal。编译子代理只写 goal，不改代码。
6. 按 host 点火 **impl**（tmux：`sh launch-runner.sh`，session `adr-<id>-<slice>`；orca：同 worktree、title `adr-<id>-<slice>-impl-<attempt>`）。每个 tick 用 `mkdir .adr/<id>/run/.lock-<phase>` 原子抢占；哨兵按 attempt/hash/mtime/HEAD 核验，不得只看固定路径存在。host=orca 时每个 tick 跑 `cleanup-orca-sessions.sh`，关掉已完成 session。主会话不得内联实现业务代码。
7. impl 完成后冻结 impl，记录待验 HEAD，写 acceptance-prompt；启动 **与 impl 不同的 reviewer**（同一 worktree）。任何同工具验收都必须先有用户明确授权；只剩一个工具只触发询问。reviewer 只写 acceptance/只读复跑测试，acceptance 外新增 diff 即 `BLOCKED`。
8. acceptance 的 attempt/hash/mtime 合法且当前 HEAD 等于 reviewed `head_sha`，结论为 `全部完成` → 本片置 `done (commit, 数字)`；有 pending 片则下一片置 `open`。
9. 结论为 `未完成` → 保持 `open`，归档本轮产物后编译修复 goal；`BLOCKED` → 置 `paused(原因)` 并通知用户。
10. 所有切片均 `done` → 最终汇总、删定时器、host=orca 再清一次已完成 session、按 control-plane 策略提交/归档 `.adr/`；确认归档且得到用户清理授权后才允许 `worktree rm`。
```

## lifecycle 交接自检

- 迁移前后 `plan_sha256` 一致，执行区 HEAD 从确认记录的 `base_sha` 起步。
- dirty 业务改动已按用户选择处理，没有静默丢弃。
- `pushurl no_push`（或等价硬禁 push）已生效。

## 切片粒度自检

- 一片 runner 时长 15-60 分钟？（超过 → 拆；不足 10 分钟 → 合）
- 后片只依赖前片 commit？（有环 → 重排）
- 每片有独立可验证的 DoD？（验不了 → 范围没想清，回 grill）
