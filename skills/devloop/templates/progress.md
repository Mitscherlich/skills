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

<!-- host / scheduler / coordinator / impl / reviewer / worktree / automation id 写这里 -->

## 决定变更与确认来源

<!-- 记录旧决定的替代原因与用户消息来源；当前生效决定回写 intent/spec 正文。联审前记录 spec/plan 草稿 hash，交接时记录最终 plan hash，避免写回 plan 自身。 -->

## 交互回放指标

<!-- 关键问题数 / 重复确认数 / 开工后需求返工 / 错误完成次数；只记实际可核对的事实，不估算未观测的用户耗时。 -->

## 巡检日志

| 时间 | 切片 | host | scheduler | runner 状态 | 提交数 | 要点 |
|---|---|---|---|---|---|---|
