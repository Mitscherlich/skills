# {{id}} · {{title}} · plan（切片验收事实源）

execution_mode: {{mode}}
runtime_host: {{runtime_host}}

> **阶段：plan（spec 编译产物）**。本文件是切片验收的事实源；acpus 模式的子任务运行状态以 Acpus Runtime 为准，不能用节点 completed 代替切片验收。
> 上游：`spec.md`
> spec_sha256: {{gate spec 通过时输出的 sha256}}
> 准出门禁：`devloop gate plan --file <本文件> --spec <spec.md>` 全绿 **且** 确认记录齐全，才能进入 loop。
> 执行区：worktree `{{绝对路径}}`（分支 `feat/devloop-{{id}}`）。host=`{{tmux|herdr|orca|acpus}}`。**绝不 push**。
> 每轮点火生成 attempt_id；产物路径含 attempt，或启动前把旧产物归档到 `run/archive/<attempt_id>/`。
> 切片状态词固定：`open`（当前在做，至多一个）/ `done (commit, 门禁数字)` / `pending` / `paused(原因)`。

## 背景与目标

{{一段话：从 spec 的「目标与验收终态」压缩而来，写清 loop 跑完时什么成立}}

## 需求追溯

> 证明 spec 的每条 `R<n>` 都被至少一个切片覆盖。门禁逐条检查 spec 的 R 已覆盖，且所引 F 确实存在。

| 需求 | 覆盖切片 | 说明 |
|---|---|---|
| R1 | F1 | {{该切片如何满足 R1}} |

## 执行前置条件

{{逐项承接 intent 的 Q ID：负责人、解决证据、阻塞切片或发布动作；无则写无。编 goal 前核验，未满足的依赖切片 paused。}}

## 相关项目知识

{{从 docs/knowledge/index.md 按本轮范围选择：项目相对文件路径、适用切片、读取用途及相关版本/commit；无相关资料则说明已查范围。goal 和 reviewer prompt 都带入本片相关路径与约束。}}

## 确认记录（进入 loop 前必填）

- 确认来源：{{实际用户消息或外部批准 ID；joint 同时覆盖 spec 与 plan}}
- 确认人：{{用户 / 责任人}}
- 确认时间：{{ISO 时间}}
- 确认范围：{{本 plan 覆盖哪些切片，哪些暂停}}
- 执行宿主（`--host`）：{{host 用 tmux|herdr|orca|自动探测；acpus 写 acpus}} —— host 以 `devloop detect-host --dir .devloop/<id>` 输出为准，acpus 不跑 host/scheduler 探测
  - 用户 `--host=` / `DEVLOOP_HOST=` 走严格 `--force`；仅偏好且允许降级时用 `--prefer`
- 哨兵调度：{{host 用 loop|orca-automation|cronjob；acpus 写 Runtime}} —— host 以 `devloop detect-scheduler` 为准
- 协调者：{{claude-code|codex|grok|omp|…}}
- Orca setup policy：{{run|skip|inherit —— 非 Orca 时写「不适用」}}
- 权限与 threat model：{{默认最小权限；若启用 bypassPermissions / danger sandbox，粘贴用户授权原文与必要性}}
- 实现 runner（`--impl`）：{{claude-code|codex|grok}}
- 对抗验收（`--reviewer`）：{{与 impl 不同的工具，或「按默认配对」}}
  - 默认配对：claude-code→codex/grok；codex→claude-code/grok；grok→claude-code/codex
- 同工具验收授权：{{无 —— 或粘贴用户明确授权原文及原因；「只剩一个工具」本身不构成授权}}
- source_worktree：{{grill 产出所在 checkout 绝对路径}}
- base_sha：{{执行 worktree 锁定的起点 SHA}}
- plan hash 记录位置：{{progress 中的交接记录；整份 plan 的 hash 不写回自身}}
- control-plane 策略：`.devloop/.gitignore` 只忽略任务过程材料；`docs/knowledge/specs/` 和知识文件纳入 Git。提交只暂存 allowlist。
- 知识回写范围：{{项目既有领域/设计/规范文档 allowlist；不写个人全局 memory}}
- 规格归位与清理：{{docs/knowledge/specs/<capability>/spec.md 及 domain/playbooks/decisions 目标；默认保留过程文件，清理需明确授权}}
- 发布与下一轮：{{默认仅准备发布交接和候选；如已有执行预授权，记录类别/路径/预算或轮次/停止条件与来源}}
- 进入 loop 结论：{{通过 / 确认进入 / 同意进入；原话留在确认来源}}

## 切片 roadmap

> host 按实现切片填写；acpus 先拆全量 T 图，再填 F 验收批次。独立功能可共用一个 F；下列 F2/F9 按真实屏障保留或删除。

| # | 切片 | 状态 | 范围（引用 R / I 编号） | DoD 附加项 |
|---|---|---|---|---|
| F1 | {{名}} | open | {{R1、R2：做什么}} | {{该片特有验收点}} |
| F2 | {{名}} | pending | {{R3：做什么}} | {{…}} |
| F9 | {{需人工输入的片}} | paused(需凭据) | **PAUSE 点**：{{需要用户提供什么}} | 到达即通知用户 |

## 每片统一 DoD（写进每份 goal）

1. 范围内新逻辑有测试；全仓门禁 {{lint/typecheck/test 命令}} 全绿。
2. 本地 commit（message 前缀 `feat({{id}}-<slice>):`），**绝不 push**。
3. impl runner 报告写 `.devloop/{{id}}/run/<impl>-<slice>-report.md`：`attempt_id`、`goal_sha256`、`base_sha`、`head_sha`、变更清单、门禁数字、设计取舍、计划偏差；先写同目录临时文件，完整落盘后 atomic rename。acpus 改用 `run/acpus/<F>/<attempt>/` 下的独立路径，保持字段和完成标准。
4. reviewer 写 `.devloop/{{id}}/run/<impl>-<slice>-acceptance.md`（acpus 使用上述隔离目录，注明 impl/reviewer 及同一组 attempt/hash，记录 reviewed `head_sha`），结论为 `全部完成` 且当前 HEAD 未漂移才能推进下一片。
5. 遇下列情况**停止并在报告写明 BLOCKED**：语义歧义无法自决 / 门禁 3 轮修复不过 / 需要外部凭据。

## loop 小周期协议

进入执行或恢复时，host 读技能的 `references/loop.md`，acpus 读 `references/acpus-mode.md`；全切片 done 后按 `references/closeout.md` 核对验收、将规格和知识归位、准备发布交接与候选。执行区交接需显式复制任务过程材料并核对 progress 记录的 plan hash，同时核对持久规格/知识版本。
