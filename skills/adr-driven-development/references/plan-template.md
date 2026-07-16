# plan.md 模板（.adr/<id>/plan.md）

grill 阶段边聊边填「决策」小节；grill 收尾时补「切片 roadmap」并取得用户确认。此文件是 loop 的**单一事实源**：哨兵与核验 agent 只认这里的状态列。没有「确认记录」不得进入 loop 或启动 tmux runner。

```markdown
# ADR <id> <标题> · plan（loop 单一事实源）

> 执行区：worktree `<path>`（分支 `feat/adr<id>-<slug>`）。**绝不 push**。
> 每片本地 commit + runner 报告落 `.adr/<id>/run/<impl>-<slice>-report.md`。
> 每片验收报告落 `.adr/<id>/run/<impl>-<slice>-acceptance.md`。
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
- 实现 runner：<--impl 值或明确命令>
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
3. runner 报告写 `.adr/<id>/run/<impl>-<slice>-report.md`：变更清单、门禁数字、设计取舍、发现的计划偏差。
4. 验收子代理报告写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`，结论为 `全部完成` 才能推进下一片。
5. 遇下列情况**停止并在报告写明 BLOCKED**：语义歧义无法自决 / 门禁 3 轮修复不过 / 需要外部凭据。

## loop 小周期协议

1. 检查确认记录存在且当前只有一个 `open` 片；否则回到 grill 或暂停。
2. 小周期 1：goal 编译子代理按 `references/goal-template.md` 写入 `.adr/<id>/next-goal.md`。「工具 goal 指令」段可用开源的 qiaomu-goal-meta-skill 生成，否则手写等价字段；编译子代理只写 goal，不改代码。
3. 小周期 2：tmux 点火 impl runner，让 runner 原样消费 `.adr/<id>/next-goal.md` 中的工具 goal 指令 + 阶段提示词完成开发；哨兵每 10min 巡检写 `progress.md`。主会话不得内联实现业务代码。
4. 小周期 3：tmux 返回后委派验收子代理做对抗式阶段验收，写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`。
5. 验收结论为 `全部完成` → 本片置 `done (commit, 数字)`；有 pending 片则下一片置 `open` 并回到小周期 1。
6. 验收结论为 `未完成` → 保持本片 `open`，把缺口编译成修复 goal，回到小周期 1；验收结论为 `BLOCKED` → 本片置 `paused(原因)` 并通知用户。
7. 所有切片均 `done` 且最后验收报告为 `全部完成` → 进入最终汇总汇报（progress.md 汇总 + 删 cron + 通知）。
```

## 切片粒度自检

- 一片 runner 时长 15-60 分钟？（超过 → 拆；不足 10 分钟 → 合）
- 后片只依赖前片 commit？（有环 → 重排）
- 每片有独立可验证的 DoD？（验不了 → 范围没想清，回 grill）
