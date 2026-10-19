
## Acpus 执行合同

> init --mode acpus 创建 plan 时追加本节。F 是按顺序验收的批次；每个批次的 T 子图交给 Acpus 并行调度。公共契约先验收，再将独立模块放进同一批次，最终集成验收通过才推进 F。

acpus_max_parallel: 3
acpus_max_attempts: 3
acpus_task_timeout_minutes: 45
acpus_run_timeout_minutes: 180

{{确认上述并发/累计尝试数/子任务及批次总时间预算；记录 acpus --version、impl/reviewer 对应的 ACP Agent、权限策略。重试、恢复和 fork 不重置本批次累计预算。}}

| 子任务 | 所属切片 | 依赖子任务 | 允许写入路径 | 验收命令与预期 |
|---|---|---|---|---|
| T1 | F1 | - | {{公共契约路径}} | {{契约与最薄链路验证}} |
| T2 | F2 | - | {{独立模块 A 路径}} | {{模块 A 验证}} |
| T3 | F2 | - | {{独立模块 B 路径}} | {{模块 B 验证}} |

{{按真实范围替换子图；每个非 paused 的 F 至少有一条 T。依赖用 T1,T2 或 -，只能引用同一 F 内的 T，不允许环。协调者检查路径、接口、schema、锁文件、端口与测试资源是否冲突；共享写入通过依赖串行化。}}

{{每个 T 单独 worktree；记录分支、起点、goal/输入快照、报告位置。明确由谁串行集成、集成后完整 DoD 与跨工具 reviewer、首次可演示检查点。状态与证据通过 Acpus inspect 展示，故障与预算耗尽通知用户。}}
