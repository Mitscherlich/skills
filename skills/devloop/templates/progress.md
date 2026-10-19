# {{id}} · {{title}} · progress

> 巡检日志与阶段状态。**非事实源**——切片状态以 `plan.md` 为准，本文件只做时间线留痕。
> 创建时间：{{created}}

## 管线状态

| 阶段 | 产物 | 门禁 | 状态 | 时间 |
|---|---|---|---|---|
| intent | `intent.md` | `devloop gate intent` | - | - |
| spec | `spec.md` | `devloop gate spec` | - | - |
| plan | `plan.md` | `devloop gate plan` | - | - |
| loop | `next-goal.md` + run/ | reviewer acceptance | - | - |

## 启动记录

<!-- execution_mode / host / scheduler / coordinator / impl / reviewer / worktree / automation id 写这里。
acpus 模式记录 CLI 路径/版本、ACPUS_HOME、Runtime workspace cwd、F/attempt/Run ID 映射、workflow 路径与 hash、累计尝试与预算起点；attemptNo 可能在组重试后重置，不作为累计计数。
运行时状态向 Runtime 查询，本文件只做定位与证据摘要，不复制一套状态机。 -->

## 决定变更与确认来源

<!-- 记录旧决定的替代原因与用户消息来源；当前生效决定回写 intent/spec 正文。联审前记录 spec/plan 草稿 hash，交接时记录最终 plan hash，避免写回 plan 自身。 -->

## 交互回放指标

<!-- 关键问题数 / 重复确认数 / 开工后需求返工 / 错误完成次数；acpus 增记关键路径耗时、重复失败原因与累计尝试。只记实际可核对的事实，缺失指标记未知，不估算未观测的用户耗时。 -->

## 巡检日志

| 时间 | 切片 | host | scheduler | runner 状态 | 提交数 | 要点 |
|---|---|---|---|---|---|---|
