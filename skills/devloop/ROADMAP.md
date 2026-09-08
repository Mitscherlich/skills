# devloop · ROADMAP

> 版本线：0.4.0 → 0.5.x（control-plane kernel）→ 0.6.x（阶段门禁）→ 0.7.0（澄清减负、联审与知识收尾）→ 0.8.0（项目知识入口与维护）→ **0.9.1（规格统一到项目知识库）** → 后续（跨会话 watch / adapter）
> 来源：相对 Claude Dynamic Workflows / acpus / LoopX 的差距分析（2026-08-06）；AI-native SDLC 分层对齐（2026-08-31）  
> 本文件是**产品演进事实源**；切片执行状态以 `.devloop/<id>/plan.md` 为准。

## 1. 结论摘要

### 1.1 定位

devloop 的差异化不在「能跑 agent」，而在**可审计交付环**：

1. 三份阶段产物与正式门禁；0.7 默认 intent 确认 + spec/plan 联审，旧流程保留分开签署
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
devloop CLI/kernel（硬）    →  状态机 · 锁 · attempt · 点火 · tick · 推进
        │
        ▼
coding agents / host adapters
```

- **要抽 control plane**：状态机、点火、tick、恢复做成独立可执行层  
- **不要抛弃 skill**：grill / plan 裁决 / goal 语义仍靠对话；skill 作薄入口  
- **不做**完整 agent OS（避免与 acpus / LoopX 正面重复）  
- **不拼** Claude DW 并行吞吐；自称「可审计跨工具交付环」

## 2. 版本规划

### 0.5.x — Control-plane kernel（已交付）

最小可执行内核，把「loop 小周期 0–3 + 哨兵」里**可漂移步骤**固化为 shell CLI：

| 能力 | CLI / 产物 | 验收 |
|------|------------|------|
| 健康检查 | `devloop doctor` | 结构、语法、PATH 探测 |
| attempt 绑定 | `devloop attempt new\|archive` | 不可复用 id + 归档旧产物 |
| 阶段锁 | `devloop lock acquire\|release` | 原子 mkdir 锁 |
| 状态机 | `devloop state validate\|transition` | 合法转移表 |
| 状态投影 | `devloop status` | 从 plan 读 open/done/pending |
| 下一步 | `devloop next` | 输出下一动作与读什么文件 |
| 审阅包 | `devloop review-packet` | 人类可读压缩摘要 |
| 统一入口 | `scripts/devloop`（0.5.x 时名为 `scripts/adr`） | 子命令分发 |
| 契约文档 | `references/control-plane.md` | skill 指向 CLI |
| skill 瘦身入口 | SKILL.md 增加 kernel 段 | 版本 ≥ 0.5.0 |

### 0.6.x — AI-native SDLC 管线（已交付）

对齐 Anthropic《The AI-native SDLC playbook》的分层，把原本一步到位的「grill → plan」拆成三段可门禁的编译链：

| 能力 | CLI / 产物 | 验收 |
|------|------------|------|
| 意图活文档 | `templates/intent.md` + `devloop init` | 边聊边回写；未决问题未收敛即挡门禁 |
| intent 准出门禁 | `devloop gate intent` | 结构 / 占位符 / 编号裁决 / 未决问题 / **人工审阅签字** |
| 设计规格编译 | `templates/spec.md` + `references/pipeline.md` 提示词 | `R<n>` 需求表 + 关注点与冲突显式暴露 |
| spec 准出门禁 | `devloop gate spec --intent` | **过程性记录残留检测** + 需求列完整 + **签署** |
| 执行计划编译 | `templates/plan.md` | 需求追溯 `R→F` + 切片 roadmap |
| plan 准出门禁 | `devloop gate plan --spec` | 追溯覆盖 + 唯一 open + 状态词合法 + **确认记录** |
| 上游漂移防护 | `intent_sha256` / `spec_sha256` 绑定 | 上游改过而下游未重编译 → 门禁失败 |
| 管线状态机 | `devloop stage can\|validate\|transitions` | 拒绝跳级；打回边合法 |
| 全管线下一步 | `devloop next --dir` | 依次跑三道门禁，返回 stage/action + fail 明细 |
| 目录迁移 | `.adr/` → `.devloop/`（硬切换） | CLI `scripts/adr` → `scripts/devloop`；env `ADR_*` → `DEVLOOP_*` |

**0.6.x 历史映射（0.7 已拆开发布状态）**：Plan→intent.md，Design→spec.md，Build→plan.md + loop，Test→impl 门禁数字，Deploy→跨工具对抗验收（devloop 只做本地 commit，不 push，故不含 branch protection / 生产发布）。Maintain 阶段（监控触发 incident intent.md）暂不在 devloop 范围内。

### 附：历史评估——不固化为 Claude Workflow（2026-08-31）

以下是当时 0.6 的三次独立签署假设与工具快照，不是 0.7 联审的执行规程；工具能力需另行核对。

Claude Workflow 是**单会话内**的确定性 JS 编排层（`agent()` / `parallel()` / `pipeline()`），脚本本身无文件系统访问、无跨会话持久化、无人工 gate 暂停能力，且有并发与总 agent 数上限。

按管线两半分别评估：

| 半段 | 适配度 | 判断 |
|---|---|---|
| intent → spec → plan | **高**：有界扇出（可并行编译多份 spec 候选 → 评审 → 合成）、单会话内可完成 | 可做，但收益有限——瓶颈是**人签字**，不是编译吞吐 |
| loop（哨兵 + tmux/Orca runner + 跨会话） | **低**：runner 活在 workflow 进程之外，哨兵按小时计跨会话，三处人工 gate 需要暂停等人 | 不可做 |

不固化的三条理由：

1. **门禁的价值在「人」不在「并发」**。三道门禁各自需要一次真人签字；Workflow 无法暂停等人，硬塞进去只会把人的门禁退化成模型自评——恰好是本 skill 最要防的东西。
2. **会引入第二事实源**。Workflow 脚本无 fs 访问，产物仍要靠 agent 写盘；编排状态与 `.devloop/<id>/` 会分叉。当前设计里 `plan.md` 是唯一事实源，这条不能破。
3. **可漂移步骤已被 shell 固化**。Workflow 想解决的「协调 agent 跳步」问题，`devloop gate` / `stage` / `next` 已经用退出码解决了，且跨会话、跨工具（codex/grok 也能调），比绑定 Claude 的 JS 编排更符合本仓库「不绑定单一厂商」的定位。

**何时重估**：Workflow 支持持久化断点与人工 gate 暂停，或 devloop 出现「一次编译多份候选再评审」的真实需求时。届时可只把阶段 2/3 的编译做成可选 front-door workflow，loop 仍留在 skill + CLI。

### 0.7.0 — 澄清减负与知识收尾（历史；外部整包及 exclude 方案已由 0.9 取代）

- 新 intent 默认 joint：只问业务目标/范围/红线的阻塞问题；后续问题按 stage/owner/due 转交，当前决定替代时同步正文。
- `gate --draft` 支持 spec/plan 联审准备；正式门禁与真实用户授权仍是点火条件。`next` 区分内容修订与等待审阅。
- plan 门禁逐条核对 R→F 覆盖与所引 F 存在，明确拒绝被打回的执行确认。
- init 默认把本任务执行目录写入 Git exclude；已跟踪文件只提示，不自动取消跟踪。
- closeout 模板/规程：核验原承诺与未验证项、回写生效项目知识、对接已有发布流程、生成少量有证据候选；默认不自动启动下一轮。
- `archive --dir --output` / `archive --verify`：Python 3 标准库，逐文件校验、外部持久保存、幂等复用、不覆盖、不删源。
- SKILL.md 按启动/执行/收尾分支加载，执行细则移到 references/loop.md，减少初始阅读负担。

本版将独立验收标为本地交付边界，发布与效果观察分别记录。后续用真实新流程测关键问题数、重复确认、开工后需求返工和错误完成次数；shell 回归测试不能证明交互效果已改善。

### 0.8.0 — 项目知识入口与维护

- `setup [--project DIR] [--check]`：幂等创建 `docs/knowledge/index.md` 和 AGENTS 入口；保留已有内容，只引用已存在的资料，分类目录按需创建。
- 入口 skill 在新开、恢复、收尾和下一轮启动时必查知识入口，缺失时调用 setup；CLI init 对目标项目只读检查并提示，不修改知识文件。
- plan 记录相关知识路径与用途，goal 和 reviewer prompt 都接收本片知识；交接时核对执行 worktree 可读。
- 收尾合并生效知识、维护替代关系和索引；CLI 的 initialized 只证明入口存在，内容和链接由 Agent 查证。
- 继续保持执行档案与长期知识分离；不接入其它知识库框架，不新增任务状态数据库。

### 0.9.0 — 持久规格与分类归位（历史；规格路径由 0.9.1 调整）

- 定稿需求维护在 `.devloop/specs/<capability>/spec.md`，同一能力增量合并，Git 保存历史；明确需求定稿不等于实现验收。
- spec 保留需求与验收契约，domain 只保存跨能力的领域公理；经验归位 playbooks，ADR 归位 decisions，并维护引用与来源。
- `.devloop/.gitignore` 仅忽略任务过程文档和 run/，持久 specs 和忽略文件可提交；setup/init 迁移可精确识别的旧根规则与本地 exclude，保留其它规则和 Git 索引。
- 移除外部 tar.gz 脚本及测试；收尾按内容归位、保存必要确认与验收依据，再按授权清理过程材料。
- 增加持久规格模板和索引；知识 setup 联动检查持久规格入口与 Git 可见性。

### 0.9.1 — 规格统一到项目知识库

- 定稿规格统一为 `docs/knowledge/specs/<capability>/spec.md`，与 domain、decisions、conventions、playbooks 共用知识入口。
- setup、模板、定稿与收尾协议统一新路径；`.devloop/.gitignore` 移除 specs 例外，只处理任务过程材料。
- 旧目录由协调者比较归并并修复引用；CLI 明确提示迁移，保留冲突原件，自动更新已知旧索引链接。

### 后续 — 跨会话与 adapter

- `devloop tick` / `devloop watch`（跨会话调度，或导出 cron/launchd）
- host adapter 接口（tmux / shell / orca）
- typed human gate + safe fallback 切片
- 简单 quota（每片 max attempt、每日 max tick）
- 可选桥接 acpus（并行子图）/ LoopX（长期 goal 投影）

### 后续 — 体验与生态

- dashboard（投影，非第二事实源）
- ACP / acpx agent map
- preset / guided start

## 3. 切片原则

1. **小而可验证**：每片独立测试；全量 `tests/*.test.sh` 全绿才算完成  
2. **测试先行**：改动前跑基线；先加/改测试再实现；实现后再跑全量  
3. **提交备份**：每片实现前记录 `BASE` commit；失败保留现场，按明确授权恢复本片改动，不自动清除用户修改
4. **零第三方依赖**：POSIX sh + 标准工具  
5. **不破坏 0.4.0 契约**：detect-runtime-host / launch-runner / 模板语义保持  
6. **串行一片 open**：单向依赖 F1→F2→…  
7. **本地 commit，不 push**（除非用户另行要求）

## 4. 成功标准（0.5.x 收官）

- [x] ≥15 个本地 commit 对应独立切片能力  
- [x] `scripts/devloop` 可 `doctor|status|next|attempt|lock|state|review-packet`  
- [x] 新增测试全绿；原有 detect-runtime-host 测试不回归  
- [x] SKILL.md / ROADMAP / control-plane 文档对齐 version 0.5.x  
- [x] 协调 agent 可用 `devloop next` 决定下一步，而无需重读全部协议

## 5. 成功标准（0.6.x 收官）

- [x] `devloop init` / `gate intent|spec|plan` / `stage` / `next --dir` 全部可用  
- [x] 三道门禁含签署字段检查；真实签署来源由协调者核验，字段检查不证明身份
- [x] `intent_sha256` / `spec_sha256` 绑定可检出上游漂移  
- [x] `.adr/` → `.devloop/` 硬切换完成，无残留命名  
- [x] `tests/*.test.sh` 全绿（14 文件 / 253 断言），含 gate、init、stage、pipeline-next 新增用例  
- [x] SKILL.md / ROADMAP / control-plane / pipeline 文档对齐 version 0.6.0
