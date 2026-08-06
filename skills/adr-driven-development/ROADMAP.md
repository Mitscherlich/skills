# adr-driven-development · ROADMAP

> 版本线：0.4.0 → 0.5.x（control-plane kernel）→ 0.6.x（跨会话 watch / adapter）  
> 来源：相对 Claude Dynamic Workflows / acpus / LoopX 的差距分析（2026-08-06）  
> 本文件是**产品演进事实源**；切片执行状态以 `.adr/<id>/plan.md` 为准。

## 1. 结论摘要

### 1.1 定位

ADR skill 的差异化不在「能跑 agent」，而在**可审计交付环**：

1. grill 门禁（设计裁决先于实现）
2. 单向依赖切片 + 统一 DoD
3. 主会话禁止内联实现
4. 跨工具对抗验收（impl ≠ reviewer 默认强制）
5. attempt / hash / atomic rename 防假完成

### 1.2 最大结构性短板

**用 prompt 当 runtime**。规程写在 350+ 行 SKILL.md 里，靠协调 agent 自觉执行；竞品已把调度做成硬约束：

| 竞品 | 硬约束形态 |
|------|------------|
| Claude Dynamic Workflows | JS 编排脚本（调度不烧 token） |
| acpus | WorkflowIR + durable run（pause/resume/retry/fork） |
| LoopX | quota / todo claim / gate 状态机 CLI |

### 1.3 其他关键差距

| 领域 | 现状 | 目标 |
|------|------|------|
| 持久化 / 恢复 | 会话级哨兵 + markdown | 可查询状态机 + 跨会话 tick |
| 可观测性 | progress 手记 + log tail | `status` / `review-packet` / `next` |
| Host 抽象 | 绑 tmux \| orca + 手写 CLI | adapter 接口 |
| Human gate | 粗粒度 `paused(原因)` | typed gate + safe fallback |
| 启动摩擦 | 依赖检查链路长 | `doctor` + 一键 next-action |
| 可测性 | 仅 host 探测脚本 | 状态机 / attempt / lock 单测 |
| 协议遵从 | 超长 prose 易跳步 | skill 瘦身，kernel 可执行 |

### 1.4 战略选择（不二选一）

```
Skill（薄，方法论 + 对话）  →  只调 CLI，不解释状态机
        │
        ▼
adr CLI / kernel（硬）       →  状态机 · 锁 · attempt · 点火 · tick · 推进
        │
        ▼
coding agents / host adapters
```

- **要抽 control plane**：状态机、点火、tick、恢复做成独立可执行层  
- **不要抛弃 skill**：grill / plan 裁决 / goal 语义仍靠对话；skill 作薄入口  
- **不做**完整 agent OS（避免与 acpus / LoopX 正面重复）  
- **不拼** Claude DW 并行吞吐；自称「可审计跨工具交付环」

## 2. 版本规划

### 0.5.x — Control-plane kernel（本 ADR 目标）

最小可执行内核，把「loop 小周期 0–3 + 哨兵」里**可漂移步骤**固化为 shell CLI：

| 能力 | CLI / 产物 | 验收 |
|------|------------|------|
| 健康检查 | `adr doctor` | 结构、语法、PATH 探测 |
| attempt 绑定 | `adr attempt new\|archive` | 不可复用 id + 归档旧产物 |
| 阶段锁 | `adr lock acquire\|release` | 原子 mkdir 锁 |
| 状态机 | `adr state validate\|transition` | 合法转移表 |
| 状态投影 | `adr status` | 从 plan 读 open/done/pending |
| 下一步 | `adr next` | 输出下一动作与读什么文件 |
| 审阅包 | `adr review-packet` | 人类可读压缩摘要 |
| 统一入口 | `scripts/adr` | 子命令分发 |
| 契约文档 | `references/control-plane.md` | skill 指向 CLI |
| skill 瘦身入口 | SKILL.md 增加 kernel 段 | 版本 ≥ 0.5.0 |

### 0.6.x — 跨会话与 adapter（后续）

- `adr tick` / `adr watch`（跨会话调度，或导出 cron/launchd）
- host adapter 接口（tmux / shell / orca）
- typed human gate + safe fallback 切片
- 简单 quota（每片 max attempt、每日 max tick）
- 可选桥接 acpus（并行子图）/ LoopX（长期 goal 投影）

### 0.7.x+ — 体验与生态

- dashboard（投影，非第二事实源）
- ACP / acpx agent map
- preset / guided start

## 3. 本轮 ADR 切片原则

1. **小而可验证**：每片独立测试；全量 `tests/*.test.sh` 全绿才算完成  
2. **测试先行**：改动前跑基线；先加/改测试再实现；实现后再跑全量  
3. **提交备份**：每片实现前记录 `BASE` commit；失败 `git reset --hard` 回滚  
4. **零第三方依赖**：POSIX sh + 标准工具  
5. **不破坏 0.4.0 契约**：detect-runtime-host / launch-runner / 模板语义保持  
6. **串行一片 open**：单向依赖 F1→F2→…  
7. **本地 commit，不 push**（除非用户另行要求）

## 4. 成功标准（0.5.x 收官）

- [x] ≥15 个本地 commit 对应独立切片能力  
- [x] `scripts/adr` 可 `doctor|status|next|attempt|lock|state|review-packet`  
- [x] 新增测试全绿；原有 detect-runtime-host 测试不回归  
- [x] SKILL.md / ROADMAP / control-plane 文档对齐 version 0.5.x  
- [x] 协调 agent 可用 `adr next` 决定下一步，而无需重读全部协议
