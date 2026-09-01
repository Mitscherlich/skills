---
name: devloop
description: Use when the user wants an unattended AI-native delivery loop (devloop), asks to turn a raw requirement into intent.md → spec.md → plan.md → verified local commits, continue an existing .devloop/<id>/ pipeline, or run implementation with stage gates, detect-runtime-host, attempt-bound handover, and cross-tool reviewer acceptance through tmux or Orca.
version: 0.6.0
---

# devloop（intent → spec → plan → loop 无人值守交付）

把一个模糊的大需求变成「已核验的一串本地 commit」。人只在四个点介入：grill 对话（裁决设计）、三道准出门禁的签字（intent 审阅 / spec 签署 / plan 确认），以及 runner 点火被权限拦截时手动执行一条命令。其余全部自动。

管线分层参考 Anthropic《The AI-native SDLC playbook》，但门禁不是 prose 提醒——是 `devloop gate <stage>` 的退出码。

**演进路线**：见 `ROADMAP.md`。**管线方法论与编译提示词**：见 `references/pipeline.md`。

## Control-plane kernel（优先调用）

协调 agent **先**用可执行 CLI 查状态/下一步，再读长规程。统一入口：

```bash
<path-to-skill>/scripts/devloop doctor
<path-to-skill>/scripts/devloop init --id <id> --title <标题>
<path-to-skill>/scripts/devloop gate intent --file .devloop/<id>/intent.md
<path-to-skill>/scripts/devloop gate spec  --file .devloop/<id>/spec.md --intent .devloop/<id>/intent.md
<path-to-skill>/scripts/devloop gate plan  --file .devloop/<id>/plan.md --spec  .devloop/<id>/spec.md
<path-to-skill>/scripts/devloop gate goal  --file .devloop/<id>/next-goal.md --spec .devloop/<id>/spec.md --plan .devloop/<id>/plan.md
<path-to-skill>/scripts/devloop next --dir .devloop/<id>
<path-to-skill>/scripts/devloop stage can --from intent --to spec
<path-to-skill>/scripts/devloop detect-host
<path-to-skill>/scripts/devloop detect-scheduler
<path-to-skill>/scripts/devloop attempt new
<path-to-skill>/scripts/devloop lock acquire --run-dir .devloop/<id>/run --phase impl
<path-to-skill>/scripts/devloop state can --from reviewing --to done
<path-to-skill>/scripts/devloop review-packet --devloop-dir .devloop/<id>
<path-to-skill>/scripts/devloop cleanup-sessions --orca-cli orca --worktree id:<repoId>::<path> --keep <live_handles>
```

**任何时候问「现在该干什么」，跑 `devloop next --dir .devloop/<id>`**，它会依次跑三道门禁并返回 `stage=` / `action=`，门禁不过时原样带出每条 `fail=`。

完整契约：`references/control-plane.md`。门禁自测：`<path-to-skill>/scripts/devloop run-tests`。

## 硬性执行契约

本 skill 的顺序不可重排：

1. **grill → intent.md**：先深挖意图，结论**边聊边回写**活文档。
2. **门禁 A**：`gate intent` 全绿 + 人工审阅签「通过」。
3. **intent.md → spec.md**：编译为 actionable 规格，**消除过程性记录**。
4. **门禁 B**：`gate spec --intent` 全绿 + 签署「通过」。
5. **spec.md → plan.md**：编译为整体方案执行计划（切片 roadmap + 需求追溯）。
6. **门禁 C**：`gate plan --spec` 全绿 + 确认记录齐全。
7. **loop 小周期**：`host 解析 → 哨兵调度裁决 → goal 编译 → 门禁 D（gate goal）→ impl runner → 跨工具验收 reviewer`，逐片串行。
8. **最终汇总**：只有验收 reviewer 汇报全部完成后，才能进入最终汇总汇报。

禁止项：

- **禁止跳级**。`devloop stage can` 会拒绝 `intent → plan`。唯一例外：用户已提供成熟的 SPEC/设计文档，可从阶段 2 起步（仍要走门禁 B/C），并在 progress.md 记下原因与文档来源。
- **禁止绕过人的门禁**。三道门禁里的「审阅人 / 签署人 / 确认人」由**人**填写，模型不得代签、不得自填自过。
- **禁止上游漂移后不重编译**。改了 intent 就要重编译 spec，改了 spec 就要重编译 plan——`sha` 绑定校验会挡住，别去改绑定值糊弄过去。
- **禁止主会话内联实现切片代码**。主会话只做 grill、编译编排、host 解析、runner 点火、巡检、核验和报告；业务代码变更必须由 **host 上的 impl runner**（tmux session 或 Orca agent terminal）完成。若 host 点火失败，记录为 `paused(待点火)` 并通知用户，**不**自动退化为内联实现；Orca 探测失败可降级 `host=tmux`，仍不得内联。
- **禁止用没过门禁 D 的 goal 点火**。`gate goal` 退出码非 0 就先修 goal；`GOAL_SHA256` 是 impl report 与 reviewer acceptance 的共同锚点，goal 中途被改会让三方 hash 对不上。
- **禁止把 runner 自报完成当成完成**。impl 退出后必须委派**验收 reviewer**（默认与 impl **不同**的 agent 工具）做对抗式检查；没有验收 reviewer 的「全部完成」结论，就不能把下一片置为 open，也不能进入最终汇总。
- **禁止默认同工具自检冒充对抗验收**。未显式指定 `--reviewer=` 时，必须按下方默认配对表选择与 `--impl` 不同的工具。**任何同工具验收都必须先取得用户明确授权，并在 plan.md 确认记录与 progress.md 写明授权原文/原因**；「只剩一个工具」只触发询问，不自动豁免。
- **禁止 next-goal.md 与 plan.md 打架**。goal 只是 plan 某一行的展开，不得新增需求、不得改切片状态；冲突时以 plan.md 为准（边界表见 `references/pipeline.md`）。

## 可选依赖（开源安装）

本 skill **零必需外部依赖**：阶段 1 的访谈算法已内联，`templates/` 已给出完整落盘结构。下列 skill 为纯增强项，缺失时走降级路径，不阻塞启动，**不需要**启动前做依赖检查。

| 阶段 | 推荐 skill / 工具 | 作用 | 安装（示例） | 缺失时降级 |
|---|---|---|---|---|
| 阶段 4 | [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT） | 把切片措辞打磨得更锐利 | `npx skills add joeseesun/qiaomu-goal-meta-skill` | 按 `templates/next-goal.md` 的七字段句式填写，效果等价 |
| host=orca | `orca-cli` skill + 本机 `orca` CLI | worktree / terminal 扇出 impl·reviewer | Orca 应用自带 CLI；会话内 `ORCA skills get orca-cli` | 降级 `host=tmux` + `scripts/launch-runner-template.sh` |

装了 `grill-me` / `grilling` 可直接用，与内联算法等价。阶段 1 的访谈算法（design tree / frontier / rounds）改写自 [mattpocock/skills](https://github.com/mattpocock/skills) 的 `grilling`（MIT）。

## 流程总览

```
阶段 1  grill 意图识别   →  .devloop/<id>/intent.md（活文档，边聊边回写）
        ── 门禁 A：devloop gate intent + 人工审阅签字 ──
阶段 2  编译设计规格     →  .devloop/<id>/spec.md（消除过程性记录，R<n> 需求表）
        ── 门禁 B：devloop gate spec --intent + 签署 ──
阶段 3  编译执行计划     →  .devloop/<id>/plan.md（切片 roadmap + 需求追溯 R→F）
        ── 门禁 C：devloop gate plan --spec + 确认记录 ──
阶段 4  loop 小周期      →  0 解析 host → 0.5 哨兵调度 → 1 goal 编译 → 2 impl runner → 3 跨工具 reviewer
收尾    最终汇总汇报     →  全部切片验收通过后，progress.md 收官条目，loop 结束
```

| host | 隔离执行区 | impl | reviewer |
|---|---|---|---|
| `tmux`（默认） | `git worktree` + `launch-runner.sh` | tmux session 跑 headless CLI | tmux/headless 另一进程 |
| `orca`（Orca 环境自动） | `orca worktree create` | 同 worktree 内 `terminal create --command <agent>` | **同一 worktree** 另一 agent terminal |

核心产物（全部在 `.devloop/<id>/`，`<id>` 形如 `0042-add-rate-limit`）：

| 文件 | 角色 |
|---|---|
| `intent.md` | 阶段 1 活文档：问题 / 期望 / 影响面 / 约束 / 编号裁决 `I-<n>` / 未决问题 / 人工审阅 |
| `spec.md` | 阶段 2 规格：目标终态 / `R<n>` 需求表 / 设计 / 关注点与冲突 / 签署（绑 `intent_sha256`） |
| `plan.md` | 阶段 3 计划：**loop 单一事实源**——需求追溯 R→F / 确认记录 / 切片 roadmap / 统一 DoD（绑 `spec_sha256`） |
| `next-goal.md` | 当前切片的自包含 goal（impl runner 的唯一输入；含 attempt 与 hash 绑定） |
| `progress.md` | 管线状态 + 巡检日志 + host/worktree/handle 记录 |
| `run/launch-runner.sh` | **仅 host=tmux**：impl 启动器（见 `scripts/launch-runner-template.sh`） |
| `run/<impl>-<slice>.log` | impl 日志（tmux: stream-json；orca: terminal read 摘要亦可） |
| `run/<impl>-<slice>-report.md` | 每片交付报告（impl 写） |
| `run/<impl>-<slice>-acceptance-prompt.md` | 验收 prompt（主会话写，reviewer 唯一输入） |
| `run/<reviewer>-<slice>-acceptance.log` | reviewer 运行日志 / 摘要 |
| `run/<impl>-<slice>-acceptance.md` | 每片验收报告（reviewer 写，全部完成/未完成/BLOCKED + impl/reviewer 头） |

## 阶段 1：grill 意图识别 → intent.md

先落盘，再开聊：

```bash
<path-to-skill>/scripts/devloop init --id <id> --title <标题>
# → .devloop/<id>/{intent.md, progress.md, run/}
```

然后**穷追不舍地访谈用户，直到双方对「要做什么」达成同一份理解**。访谈算法与活文档纪律是一件事，不是两件：

1. **建 design tree、算 frontier**：把待澄清的东西建模成决策树——一个决策的答案会解锁或改写它下游的决策；**frontier（前沿）** = 所有「前置条件已定、现在就能问」的决策。
2. **一轮把整个 frontier 一次性问完**：每题编号，并**给出你推荐的答案**。这个格式是给用户看的交互契约，原样保留：

   ```
   ❓ **Q1** - **<问题标题>**：<问题正文>
   ➡️ <你推荐的答案>
   ```

3. **查证事实是你的活，永远不是用户的活**：现有实现长什么样、某接口有没有被别处依赖、仓库既有约定是什么——**派子代理去 grep / 读代码**，只把真正需要人拍板的取舍留给用户。
4. **用户答完当场回写 intent.md**，不攒到最后补记：已定的裁决追加进 `## 裁决记录` 编号列表（`I-1` / `I-2` …，spec 需求表「来源」列会引用这些编号）；被答案推翻的问题陈述 / 期望结果 / 影响范围 / 约束**原地改写**，不在文末堆「修订说明」——过程留痕交给 git 与 progress.md；这一轮还答不了的进 `## 未决问题` 的 `- [ ]`。
5. **重算 frontier 开下一轮；frontier 为空即访谈结束**——这与门禁的 `I-openq`（`## 未决问题` 无未勾选 `- [ ]`）**是同一件事的两种说法**，门禁是「访谈是否真收敛」的机器判据。收敛后 `## 未决问题` 写成一行 `- 无`。

覆盖面：所有会影响**架构边界、写入范围、验收标准、凭据/人工输入、执行深度**的问题都要有裁决。

若仓库根存在 `CONTEXT.md`，访谈时沿用其中术语，冲突当场指出并回写 `## 裁决记录`。若本次任务本身在改领域模型且装了 `domain-modeling` skill，可另行调用它维护词汇表与 ADR——它的产物在 repo 根（`CONTEXT.md` / `docs/adr/`），与 devloop 的 `.devloop/<id>/` 互不覆盖，也不进 devloop 门禁。

### 门禁 A：intent 准出

```bash
<path-to-skill>/scripts/devloop gate intent --file .devloop/<id>/intent.md
```

失败时按 `fail=` 逐条回填，**不要**改门禁去迁就文档。检查项见 `references/pipeline.md`。

`## 人工审阅` 是**人的门禁**：审阅人要真的读过 intent 全文，模型不得代签。结论写「打回」时回到 grill，不得往下走。门禁通过时 stdout 的 `sha256=` 就是下一阶段要写进 `intent_sha256:` 的值。

## 阶段 2：intent.md → spec.md（编译）

派编译子代理，prompt 见 `references/pipeline.md` 的「阶段 2」（改编自 playbook 的设计提示词，保留「加载组织规范 + 显式暴露策略冲突」两个要点）。要点：

- 结构按 `templates/spec.md`（`devloop init --id <id> --stage spec` 可落骨架）。
- **消除过程性记录**：不得出现裁决历史、未决问题、问答轮次、grill 对话痕迹。intent 的裁决只以 `I-<n>` 出现在需求表「来源」列。
- 每条需求一个稳定 ID `R<n>`，**验收标准必须可执行**（可跑的命令 / 可 grep 的断言 / 可观测的指标）。
- `## 关注点与冲突` 宁可写「无」，也不要藏起真实的策略冲突——这是本阶段对下游最有价值的输出。
- 头部写 `intent_sha256: <门禁 A 输出的 sha256>`。
- 子代理只写 spec.md，不改业务代码、不提交。

### 门禁 B：spec 准出

```bash
<path-to-skill>/scripts/devloop gate spec --file .devloop/<id>/spec.md --intent .devloop/<id>/intent.md
```

`S-procedural*` 检查即「消除过程性记录」的机器判据；`S-bind` 挡住 intent 改过而 spec 没重编译的沉默漂移。`## 签署记录` 由人签。

## 阶段 3：spec.md → plan.md（编译）

派编译子代理，prompt 见 `references/pipeline.md` 的「阶段 3」。要点：

- 结构按 `templates/plan.md`。头部写 `spec_sha256: <门禁 B 输出的 sha256>`。
- **需求追溯表**给出 `R<n> → F<n>` 映射，每条 R 都要被至少一个切片覆盖。
- 切片粒度：一片 ≈ 一次无人值守 session 能完成的量（15–60 分钟 runner 时长、一二十个文件改动）。太大会撞上下文/限流，太小浪费点火开销。
- 切片间**依赖单向**（后片只依赖前片的 commit），禁止环。
- 涉及外部凭据/人工输入的片放最后并标 `paused(原因)`，到达时通知用户而不是硬跑。
- 状态词固定：`open`（**至多一个**）/ `done (commit, 门禁数字)` / `pending` / `paused(原因)`。
- 写清「每片统一 DoD」：门禁命令 + 全绿标准、commit message 前缀、报告路径、BLOCKED 停机条件。

### 门禁 C：plan 准出 + 用户确认

```bash
<path-to-skill>/scripts/devloop gate plan --file .devloop/<id>/plan.md --spec .devloop/<id>/spec.md
```

门禁全绿后**必须问用户确认是否进入 loop**，并把结论写进 `## 确认记录`：确认人 / 确认时间 / 确认范围 / 允许的 `--impl` 与 `--reviewer`（可写「按默认配对」）/ `--host`（可写「自动探测」）/ 权限授权 / `source_worktree` / `base_sha` / `plan_sha256` / control-plane 策略 / 进入 loop 结论。

**沉默、默认假设、模型自行判断都不算确认。** 没有确认记录不得创建 runner。

### `.devloop` lifecycle 与执行区交接

grill 可以先在当前 checkout 写 `.devloop/<id>/`，但进入执行 worktree 前必须完成以下交接，不能假设未提交文件会自动出现：

1. 在已确认 plan 中记录 `source_worktree`、执行区锁定的 `base_sha` 与原文件的 `plan_sha256`。
2. 创建目标 worktree 后，由协调者用 `cp -a <source>/.devloop/<id> <target>/.devloop/` 或等价 `rsync` 迁入；重新计算并核对 `plan_sha256`，不一致即暂停。
3. 若实现依赖 source checkout 的 dirty、未提交业务改动，暂停让用户明确选择：先 commit、生成 patch 并显式导入，或改用当前 checkout。禁止静默丢弃、猜测性复制或从错误 base 启动。
4. `.devloop/` 是 control-plane；默认建议与 feature 分支一起 commit，使 intent/spec/plan/report/acceptance 可审计。若 plan 选择不提交，则必须列出每片允许的 control-plane dirty path，impl 暂存只用路径 allowlist，避免无边界 `git add -A`。
5. 收尾先确认 `.devloop/` 已随分支提交或另行归档并记录位置；只有得到用户对归档与清理的确认后，才允许 `worktree rm`。

## 阶段 4：loop 小周期

进入阶段 4 前先跑 `devloop gate plan` 并检查确认记录；缺失就回到阶段 3，不创建 runner。

### 0. 解析执行宿主 host（进入 loop 时必做）

**唯一权威入口**：跑 skill 内脚本，消费其 stdout，不要手写探测逻辑。

```bash
<path-to-skill>/scripts/devloop detect-host                 # 自动（推荐）
<path-to-skill>/scripts/devloop detect-host --force orca    # 用户指定 --host=orca|tmux 时
<path-to-skill>/scripts/devloop detect-host --prefer orca   # 仅偏好，不可用时允许降级
<path-to-skill>/scripts/devloop detect-host --json          # 机器可读
```

脚本输出 `key=value`（或 `--json`），至少读这些字段：

| 字段 | 含义 |
|---|---|
| `host` | `orca` 或 `tmux` — **直接采用，勿再推理** |
| `reason` | 决策说明，写入 progress.md |
| `orca_cli` | 后续 Orca 命令用的可执行名/路径（host=orca 时必用） |
| `orca_status` | `ok` / `fail` / `missing` / `skip` |
| `tmux_available` | `0`/`1` |
| `orca_worktree_id` | 环境注入的当前 worktree（可能为空） |

优先级（脚本已内置，agent 只需传参）：

1. 用户 `--host=` / 环境变量 `DEVLOOP_HOST` / 脚本 `--force`：严格选择；不可用即非零退出，不降级。
2. 脚本 `--prefer`：优先目标 host；不可用时允许降级并在 `reason` 记录。
3. 自动：Orca 信号 + CLI `status` 健康 → `orca`，否则偏好式降级 `tmux`。`--force tmux` 必须完全不探测、不调用 Orca。

| 退出码 | 含义 |
|---|---|
| 0 | 选出的 host 可跑 |
| 1 | 不可跑（如 force orca 但 CLI 挂、或 tmux 不在 PATH）→ progress 记 `paused`/降级说明，**不得内联实现** |
| 2 | 参数错误 |

将 `host`、`orca_cli`（若有）、`reason`、impl/reviewer 原样写入 plan 确认记录与 progress 启动行。
`host=orca` 时的 worktree/terminal 扇出步骤见 `references/orca-host.md`（**只在 host 已定为 orca 后**再读，避免无谓烧 token）。

### 0.5 解析哨兵调度（进入 loop 时必做）

host 定下来之后、创建哨兵之前，**必须**跑调度探测。协调者（主会话 harness）和 impl/reviewer 不是一回事：Orca 里用 omp 当协调者很常见，omp **没有** `/loop`。

```bash
<path-to-skill>/scripts/devloop detect-scheduler
<path-to-skill>/scripts/devloop detect-scheduler --json
```

| 字段 | 含义 |
|---|---|
| `coordinator` | `claude-code` / `codex` / `grok` / `omp` / `pi` / `unknown` |
| `loop_supported` | `1` 才能用 `/loop`；仅 `claude-code` / `codex` / `grok` |
| `orca_env` | `1` = 当前在 Orca |
| `scheduler` | `loop` / `orca-automation` / `cron` / `ask` — **直接采用，勿再推理** |
| `reason` | 写入 progress.md |

| 退出码 | 含义 |
|---|---|
| 0 | 调度已决定（`loop` / `orca-automation` / `cron`） |
| 1 | `scheduler=ask`：必须停下来问用户 |
| 2 | 参数错误 |

按 `scheduler=` 执行（禁止自己改判）：

- **`loop`**：当前协调者支持 `/loop`，直接建每 10 分钟的 `/loop`（避开整点分钟）。
- **`orca-automation`**：协调者没有 `/loop`，但人在 Orca。**自动**用 Orca automations 当哨兵，并**告知用户**：当前协调者是 `<coordinator>`，不支持 `/loop`，已改用 Orca automation，不必换 agent。不要再问「cron 还是换人」，也不要另建 crontab。
  - `ORCA automations create --name devloop-<id>-sentinel --trigger "<避开整点的 10 分钟 cron>" --workspace active --reuse-session --prompt "<tick prompt>" --json`
  - `--reuse-session` 打回当前协调者会话；`--provider` 以 `ORCA automations create --help` 为准，不要另开第二个协调者。
  - 把 automation id 写入 progress / plan 确认记录。
- **`ask`**：不支持 `/loop`，也不在 Orca。告诉用户当前协调者不支持 `/loop`，请选：本机 cronjob / launchd，或换 claude-code / codex / grok 再进 loop。未选之前 progress 记 `paused(待选哨兵调度)`，不创建 cron、不点火。
- 用户已书面选定后才用 `--force loop|cron|orca-automation`。`--force loop` 在 `loop_supported=0` 时仍会 `ask`。

### 隔离执行区

- **host=tmux**：`git worktree add`，分支 `feat/devloop-<id>-<slug>`。
- **host=orca**：`ORCA worktree create --name devloop-<id>-<slug> ...`（优先 `--parent-worktree active`），**一个 devloop 一个 Orca worktree**；impl 与 reviewer **共用该 checkout**（禁止为 reviewer 再开平行 worktree 导致看不到 impl commit）。plan 必须记录 `setup=run|skip|inherit`。

完成 lifecycle 交接后，在执行 worktree 立刻运行 `git config remote.origin.pushurl no_push`（或等价的无效 push URL）做硬禁 push，并验证配置生效。`.devloop/<id>/` 放在 worktree 内按 plan 的 control-plane 策略随分支走；**绝不 push**。

Orca 详细命令与扇出步骤见 `references/orca-host.md`；操作前应 `ORCA skills get orca-cli` 核对当前 CLI 语法。

### 哨兵（定时巡检）

只在 `detect-scheduler` 给出 `scheduler=loop|orca-automation|cron` 之后创建哨兵。间隔 10 分钟，选一个避开整点的分钟数。多数定时器是会话级：协调者退出即 loop 停止。每个 tick 先用 `devloop lock acquire --run-dir .devloop/<id>/run --phase <compile|impl|review|advance>` 抢阶段锁；未抢到就退出，锁拥有者结束时释放，避免重复扇出 reviewer/重复推进。

定时任务的 prompt 要求每次：

1. 一次命令汇总：
   - **tmux**：session 存活性、日志行数、`tail -c 2000`、`git log --oneline -3`、`devloop next --dir .devloop/<id>`
   - **orca**：`terminal list` / `terminal read`、报告文件是否出现、`git log --oneline -3`（在执行 worktree path）、`devloop next --dir .devloop/<id>`；并立刻做下面第 6 步的 session 清理
2. 停滞判定：runner/agent 仍在但日志或文件无进展 → 记「疑似停滞×N」，连续 2 次**主动通知用户**。
3. 往 `progress.md` 巡检表**追加一行**（时间/切片/host/scheduler/runner 状态/提交数/要点）。
4. impl 完成（当前 attempt 的报告齐且该片仍 open）→ 进入小周期 3 跨工具 reviewer。
5. loop 收官后删除该定时任务。
6. **host=orca 时每个 tick 必须清理已完成 session**（见下）。Orca 子任务会留下独立 terminal/session，不关就会一直占内存。

完成哨兵不得只检查固定路径文件存在。当前产物必须满足：`attempt_id` 与本轮一致；`goal_sha256` 与当前 goal 一致；报告/验收的 mtime 晚于本轮 goal 与归档动作；报告的 `base_sha`、`head_sha` 可验证。re-open 切片前必须把上一轮 report/acceptance 移入 `run/archive/<attempt_id>/`（`devloop attempt archive`），或改用含 attempt 的新产物路径。

#### host=orca：清理已完成 session

每个 tick、以及 impl / reviewer / compiler 的产物已被本轮消费之后，跑：

```bash
<path-to-skill>/scripts/devloop cleanup-sessions \
  --orca-cli <detect-host 给出的 orca_cli> \
  --worktree id:<repoId>::<path> \
  --keep <coordinator_handle>,<current_impl_handle>,<current_review_handle> \
  --title-prefix devloop-<id>- \
  --also-close <progress 里已结束的旧 handle>
```

规则：

- `--keep` 只留协调者自己、当前仍 live 的 impl、当前仍 live 的 reviewer。
- 脚本会关：`worktree ps` 里 `state=done` 的 agent terminal、title 含 `devloop-<id>-` 的遗留 tab、以及 `--also-close`。
- **禁止** `terminal stop --worktree`（会停掉整个 worktree）。
- **禁止** 未获用户确认就 `worktree rm`。
- 关完把 `closed=` 写入 progress；handle 失效只记一笔，不重试双关。

### 小周期 1：goal 编译

每片每次点火生成不可复用的 `attempt_id`（`devloop attempt new`），再委派 goal 编译子代理：

- 输入：spec.md 中本片覆盖的 `R<n>` 原文 + plan.md 的该片行与统一 DoD + 相关裁决 `I-<n>` + 上一片报告 + 现状代码锚点。
- **结构契约**：输出必须符合 `templates/next-goal.md`（自包含 next-goal.md）。
- **工具 goal 指令段**：按 `templates/next-goal.md` 的七字段句式填——目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件。句式已内联，**不依赖外部 skill**；装了 `qiaomu-goal-meta-skill` 可用它打磨措辞后原样写入该段。**其余段落始终按模板补齐**。
- **职责边界**：goal 是 plan 某一行的展开——只能引用 `R<n>`，不得新增需求；只读切片状态，不得写入或推进；统一 DoD 原样复制、只可追加不可删减。冲突时以 plan.md 为准。发现「本片按 plan 写的范围做不出来」，在 goal 写 `BLOCKED` 并回阶段 3 修 plan，**不得**自行改范围。
- ⚠️ **写入路径必须显式写绝对路径到 worktree 的 `.devloop/<id>/next-goal.md`**。血泪教训：agent 曾写到主仓导致 runner 读到旧 goal 困惑退出。prompt 里把目标路径原文写出来并要求 agent 写完后自检。
- goal 编译 agent 只写 next-goal.md，不改业务代码、不提交、不点火。
- next-goal.md 顶部记录 `attempt_id`、`spec_sha256`、`plan_sha256`、`goal_sha256`、`base_sha`、编译时 `head_sha`；impl report 与 acceptance 必须回写同一组绑定字段以及各自产生时的 `head_sha`。

详见 `references/goal-template.md`。完成标准是**门禁 D 退出码为 0**，不是子代理自报完成：

```bash
<path-to-skill>/scripts/devloop gate goal --file <worktree>/.devloop/<id>/next-goal.md \
  --spec .devloop/<id>/spec.md --plan .devloop/<id>/plan.md
```

它校验八个必备小节、七字段齐全、九个 header 字段非空、`GOAL_SHA256` 自校验，以及 spec/plan 无漂移。不过门禁不得点火。

### 小周期 2：impl runner 实现

runner 的唯一任务输入是 `.devloop/<id>/next-goal.md`（工具 goal 指令 + 阶段提示词）；必须原样消费，不得依赖主会话上下文。

#### host=tmux

首次进入小周期 2 时，从 `scripts/launch-runner-template.sh` 复制到 `.devloop/<id>/run/launch-runner.sh`，按模板注释改完五处配置（包括 `DEVLOOP_ID`、worktree 绝对路径、impl 名称、代理、impl 命令行）：

- **绝对路径**：tmux 新 session 不继承 shell；PATH/cwd 显式写。
- **不走交互式别名**：含 `read` 的代理别名会卡死无人值守 session。
- **stream-json 日志 tee 落盘**：哨兵靠行数与 tail 判进展。
- **权限 flag 必改**：默认使用工具的最小权限（Codex 为 `--sandbox workspace-write`）；模板中的 `bypassPermissions` / danger 例子只有 plan 已记录用户明确授权时才能启用。

点火：

```bash
tmux new-session -d -s devloop-<id>-<slice> 'sh <worktree>/.devloop/<id>/run/launch-runner.sh <slice>'
# 或先 chmod +x，再直接执行 launcher
```

被权限拦截时 progress 记「待点火」，给用户可 `!` 执行的完整命令；下一 tick 可重试。

一片一个 tmux session（`devloop-<id>-<slice>`）。同一时间只有一个 impl 在跑。

#### host=orca（扇出 impl agent）

细节见 `references/orca-host.md`。摘要：

1. 确保 Orca worktree 已存在，记录 `worktree.id` = `<repoId>::<path>`。
2. 在该 worktree 扇出 **impl** terminal（agent 映射：`claude-code`→`claude`，`codex`→`codex`，`grok`→`grok`）：

```text
ORCA terminal create --worktree id:<repoId>::<path> --title devloop-<id>-<slice>-impl-<attempt> --command <impl_command_with_plan_authorized_permissions> --json
ORCA terminal wait --terminal <impl_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <impl_handle> --text "Read and execute <ABS>/.devloop/<id>/next-goal.md; write report to <ABS>/.devloop/<id>/run/<impl>-<slice>-report.md; local commit only; never push; do not edit plan.md status." --enter --json
```

3. **完成判定按 attempt 哨兵协议**：不能只看固定路径存在；核对 report 的 `attempt_id` / `goal_sha256` / `base_sha` / `head_sha`、mtime 与 commit；不要只听 agent 口述。
4. progress 记录 `impl_handle`；create 响应优先取 `agentTerminalHandle`，兼容 `startupTerminal.handle`。handle 失效时用 `terminal list` 按 worktree+完整 title+command 重取，禁止双发。
5. 可选：`worktree set --workspace-status in-progress` / `--comment "…"`。

### impl 与 reviewer 选项

用户可用 `--impl=` / `--reviewer=` / `--host=`。未指定时：

- **host**：以 `devloop detect-host` 输出为准（勿手推）
- **impl 默认**：`claude-code`
- **reviewer 默认**：与 impl **不同** 的 agent（见配对表）

| 工具 | Orca agent id | host=tmux 启动核心（impl 读 next-goal；reviewer 读 acceptance-prompt） |
|---|---|---|
| `claude-code` | `claude` | `claude -p --permission-mode default --verbose --output-format stream-json < <input>`；仅 plan 记录授权后可改 `bypassPermissions` |
| `codex` | `codex` | `codex exec --sandbox workspace-write - < <input>`；`--full-auto` 是废弃别名，有权限扩大与未来移除风险 |
| `grok` | `grok` | `grok --prompt-file <input> --output-format streaming-json`；仅 plan 记录授权后可加 danger/bypass 模式 |

goal / 验收 prompt 内容与 host 无关——产物自包含。

#### 默认 reviewer 配对（`--reviewer` 未指定时强制应用）

| impl | 默认 reviewer（按优先级，取本机**已安装且可执行**的第一个） |
|---|---|
| `claude-code` | `codex` → `grok` |
| `codex` | `claude-code` → `grok` |
| `grok` | `claude-code` → `codex` |

解析规则：

1. 用户显式 `--reviewer=X`：用 X；若 `X == impl`，**警告**并请用户明确授权；未授权不得启动同工具验收。
2. 用户未指定：按上表选与 impl 不同的工具。
3. 候选均不可用或只剩一个工具：告知用户并询问是否授权同工具；**不得**静默同工具验收。
4. 将最终 `host` / `impl` / `reviewer` 写入 plan 确认记录与 progress。

### 小周期 3：跨工具对抗验收（reviewer）

impl 完成后，必须启动 **reviewer**（默认 ≠ impl）。主会话**不得**仅凭自身通读 diff 代替 reviewer 下「全部完成」。

#### 启动前

1. 解析 `impl` / `reviewer` / `host`。
2. 核对 impl 已退出/idle，冻结其 terminal；记录当前 HEAD。主会话写自包含验收 prompt 到 worktree 绝对路径：
   `.devloop/<id>/run/<impl>-<slice>-acceptance-prompt.md`
   （含切片原文、覆盖的 `R<n>` 验收标准、路径、git 范围、门禁、验收报告输出路径、`attempt_id` / `goal_sha256` / `base_sha` / 待验 `head_sha`、对抗清单、结论三选一）。
3. 按 host 启动 reviewer：

**host=tmux** — headless / tmux session，日志 tee 到 `run/<reviewer>-<slice>-acceptance.log`：

| reviewer | 命令骨架 |
|---|---|
| `claude-code` | `claude -p --permission-mode default --verbose --output-format stream-json < "$PROMPT"`；bypass 仅限已记录授权 |
| `codex` | `codex exec --sandbox workspace-write - < "$PROMPT"`（只允许 acceptance 路径） |
| `grok` | `grok --prompt-file "$PROMPT" --output-format streaming-json`；danger/bypass 仅限已记录授权 |

**host=orca** — **同一 worktree** 再扇出 reviewer terminal（agent id 用映射表）：

```text
ORCA terminal create --worktree id:<repoId>::<path> --title devloop-<id>-<slice>-review-<attempt> --command <reviewer_command_with_plan_authorized_permissions> --json
ORCA terminal wait --terminal <review_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <review_handle> --text "Execute acceptance prompt at <ABS>/...-acceptance-prompt.md; write ONLY <ABS>/...-acceptance.md (impl=/reviewer= header; 全部完成|未完成|BLOCKED). No code changes, no commit, no plan.md status edits." --enter --json
```

完成判定：acceptance 必须按 atomic rename 发布，且 attempt/hash/mtime/结论全部合法；当前 HEAD 必须等于 acceptance 的 reviewed `head_sha`。可选 `workspace-status in-review`。

#### 对抗检查清单（写入 prompt，reviewer 必须逐项给证据）

1. next-goal.md 的验收 checklist 是否逐项满足。
2. 本片覆盖的 spec 需求 `R<n>` 的验收标准是否逐条可复现地满足。
3. runner 报告是否存在，是否包含门禁数字、变更清单、偏差说明，且没有未处理的 BLOCKED。
4. commit 是否真实产生，提交范围是否只覆盖本切片。
5. 相关门禁是否真实运行且无回归；门禁数字要能从日志或报告追溯。
6. roadmap 状态是否未被 runner 擅自推进。
7. （对抗加码）主动寻找：遗漏边界、测试未覆盖路径、与 spec 决策冲突、虚假门禁（报告数字与日志不符）。

#### 验收产出

reviewer 写 `.devloop/<id>/run/<impl>-<slice>-acceptance.md`（文件头注明 `impl=` / `reviewer=` / `attempt_id=` / `goal_sha256=` / `base_sha=` / reviewed `head_sha=`），结论只能是：

- `全部完成`：主会话把本片置 `done (commit, 数字)`；若还有 pending 切片，把下一片置 `open` 并回到小周期 1。
- `未完成`：指出缺口；可自动修复时，保持本片 `open`，重新进入小周期 1 编译修复 goal。
- `BLOCKED`：写清需要的人类决策/凭据/外部条件，把本片置 `paused(原因)` 并通知用户。

reviewer 只写验收报告与（可选）只读复跑门禁；**不改业务代码、不 commit、不推进 roadmap**。review 前后比较 worktree diff；acceptance 允许路径之外出现任何 reviewer 新增 diff，一律判 `BLOCKED`。报告/acceptance 应先写同目录临时文件，完整落盘后再 atomic rename 到哨兵路径，避免 tick 读到半文件。状态推进仍由主会话根据验收结论执行；推进前用 `devloop state can --from reviewing --to done` 校验，并再次验证当前 HEAD 等于 reviewed `head_sha`。

## 收尾

最后一片 done 后：

1. 确认每片都有 impl runner 报告与 reviewer 验收报告，且最后一份验收报告结论为 `全部完成`；验收报告头应写明 `impl` / `reviewer` / attempt/hash/SHA 绑定（及 host 若适用）。
2. **需求闭环核对**：spec.md 的每条 `R<n>` 都能在 plan 的需求追溯表找到覆盖切片，且该切片已 `done`。有 R 落空即未收尾。
3. 对抗式全量核验（仍优先用与 impl 不同的 reviewer，或主会话在 reviewer 报告上二次核对）：全部切片 commit 齐、门禁最终数字、报告齐、验收报告齐。
4. 在 `progress.md` 写收官条目（管线状态表补齐 + 每片 commit/测试数/host/impl/reviewer/成本汇总表）。
5. 若项目有全局进展文档（如 `docs/STATUS.md`、changelog、kb progress），补一条**简短**收官记录——per-tick 日志留在 `.devloop/<id>/progress.md`，不要污染全局文档。
6. 删哨兵定时任务；host=orca 时先再跑一遍 `cleanup-sessions`（`--keep` 只留协调者），再 `worktree set --workspace-status completed` 并更新 comment。
7. 按 plan 的 control-plane 策略提交或归档 `.devloop/`，记录归档位置；通知用户 loop 结束 + 待人工验收清单（如有）。**未确认归档且未经用户明确同意，不得 `worktree rm`**。

## 常见故障对照表

| 症状 | 原因 | 处置 |
|---|---|---|
| `gate intent` 卡在 `I-openq` | grill 没收敛，还有未勾选未决问题 | 回 grill 逐条裁决；确实不做的降级写进「非目标」 |
| `gate spec` 报 `S-procedural` | spec 里残留了裁决历史/问答体 | 重编译 spec，过程性内容只留在 intent.md |
| `gate spec` / `gate plan` 报 `*-bind` 漂移 | 上游改过但下游没重编译 | **重编译下游**，不要手改绑定值糊弄 |
| `gate plan` 报 `P-trace` | 需求追溯表缺 R→F 映射 | 补映射；有 R 无处安放说明切片划错，回阶段 3 |
| `gate plan` 报 `P-open` | open 切片不是恰好 1 个 | 修 roadmap 状态列 |
| 门禁通过但模型自己签了字 | 违反人的门禁 | 作废该签字，退回让人审阅；在 progress 记录 |
| runner 退出、无报告、有未提交改动 | API 限流 / session 超时 | 重启 impl（tmux 或 orca terminal），续跑捡起改动 |
| runner 秒退、日志显示困惑 | next-goal.md 是旧片内容 | goal 写错路径——检查是否写进了主仓；修正后重启 |
| 自动点火被权限拦截 | 安全分类暂不可用 | 记「待点火」，给用户 `!` 命令；下一 tick 重试 |
| 日志/终端连续两 tick 无进展 | runner 卡死 | tmux: kill 对应 session；orca: 先核对 handle/title，再 `terminal close --terminal <handle>` 并 create 重扇出；**禁止**默认用 `terminal stop --worktree`；多次则拆片 |
| 报告含 BLOCKED | 语义歧义 / 门禁不过 / 缺凭据 | 读报告定位：可自决的编修复 goal，需人工的置 paused 通知 |
| goal 里出现 plan 没有的需求 | goal 编译越界 | 作废该 goal 重编译；越界内容若确实必要，回阶段 2/3 走门禁 |
| 访谈发散、收不了尾 | frontier 没建对，问题没按依赖分层 | 回去补 design tree；未决问题逐条裁决，或降级写进「非目标」 |
| 验收被主会话直接放行 | 未启动跨工具 reviewer | 补写 acceptance-prompt 并按 host 启动 reviewer；同工具须用户书面确认 |
| reviewer CLI / agent 不存在 | 配对候选均未安装 | 告知缺失；不得静默同工具 |
| 探测到 Orca 但 worktree/terminal 失败 | CLI 旧 / app 未就绪 | `ORCA open` + `skills get orca-cli`；重跑 `detect-host`，失败则 tmux |
| reviewer 看不到 impl commit | 误开了第二个 worktree | 强制同一 `worktree.id`；废掉平行树后重跑验收 |
| `terminal_handle_stale` | Orca 重启或 handle 过期 | `terminal list` 取新 handle，只对新 handle send |
| agent 自行猜 host 与脚本不一致 | 未跑 detect 脚本 | **以脚本 stdout 为准**；重跑并覆盖 plan/progress |
| 协调者是 omp 且不在 Orca，却去建 cron / 假装 `/loop` | 未跑 `detect-scheduler` 或把 ask 当成 cron | **停下来问用户**：换 claude-code / codex / grok，或明确授权 cronjob；未选不得点火 |
| 协调者无 `/loop` 且在 Orca，却去问用户或建 crontab | 应自动走 Orca automation | 按脚本 `scheduler=orca-automation` 建 automation 并告知用户，不要再问 |
| Orca 内存持续涨、terminal 越积越多 | 已完成 impl/review session 未关 | 每个 tick 跑 `devloop cleanup-sessions`；只 keep 当前 live handle |

## 参考

- `references/pipeline.md` — **四阶段管线方法论 + 四道门禁检查表 + 编译提示词**（阶段 1–3 必读）
- `references/control-plane.md` — `devloop` CLI 契约与两套状态机
- `references/goal-template.md` — goal 编译子代理的派活手册
- `references/orca-host.md` — host=orca 时 orca-cli worktree / impl·reviewer 扇出手册（**host 已定为 orca 后再读**）
- `templates/intent.md` · `templates/spec.md` · `templates/plan.md` · `templates/next-goal.md` · `templates/progress.md` — 各阶段落盘结构（`devloop init` 使用）
- `scripts/gate.sh` — **四道准出门禁唯一入口**（intent / spec / plan / goal）
- `scripts/detect-runtime-host.sh` — **host 探测唯一入口**（进入 loop 必跑）
- `scripts/detect-loop-scheduler.sh` — **哨兵调度探测唯一入口**（`/loop` → Orca automation → 再问）
- `scripts/cleanup-orca-sessions.sh` — host=orca 时清理已完成 terminal/session
- `scripts/launch-runner-template.sh` — host=tmux 时 impl runner 启动器模板
