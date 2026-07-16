---
name: adr-driven-development
description: Use when the user wants an ADR-driven unattended delivery loop, asks to slice a large requirement into verified local commits, continue an existing .adr/<id>/plan.md loop, or run implementation through tmux with an --impl runner.
version: 0.1.0
---

# ADR 驱动开发（grill → loop → tmux 无人值守实现）

把一个模糊的大需求变成「已核验的一串本地 commit」的完整流水线。人只在两个点介入：前期 grill 对话（裁决设计），以及 tmux 点火被权限拦截时手动执行一条命令。其余全部自动。

## 硬性执行契约

本 skill 的顺序不可重排：

1. **grill 门禁**：先深挖意图、裁决方案和实现深度，写出 plan.md，并取得用户对 plan 的明确确认。
2. **loop 小周期**：只在 plan 已确认后，按「goal 编译 → tmux runner → 验收子代理」串行推进切片。
3. **最终汇总**：只有验收子代理汇报全部完成后，才能进入最终汇总汇报。

禁止项：

- **禁止跳过 grill 直接实现**。只有两种例外：用户明确说已有设计可跳过 grill，或 `.adr/<id>/plan.md` 已存在且包含已确认的「决策 + roadmap + DoD」。例外也要在 progress.md 记下原因。
- **禁止主会话内联实现切片代码**。主会话只做 grill、plan/goal 编排、runner 点火、巡检、核验和报告；业务代码变更必须由 tmux runner 完成。若 tmux 不可用或点火被拦截，记录为 `paused(待点火)` 并通知用户，不自动退化为内联实现。
- **禁止把 runner 自报完成当成完成**。runner 退出后必须委派验收子代理做对抗式检查；没有验收子代理的「全部完成」结论，就不能把下一片置为 open，也不能进入最终汇总。

## 可选依赖（开源安装）

本 skill **可独立使用**：`references/plan-template.md` 与 `references/goal-template.md` 已给出完整落盘结构。下列 skill 为推荐增强，缺失时走降级路径，不阻塞启动。

| 阶段 | 推荐 skill | 作用 | 安装（示例） | 缺失时降级 |
|---|---|---|---|---|
| 阶段 1 | `grilling` / `grill-me` / `grill-with-docs` | 需求深挖访谈 | 按你所用 agent 生态安装同名 skill（如 superpowers 的 grilling） | 用户提供现成设计/ADR/SPEC，跳过 grill 访谈 |
| 小周期 1 | [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT） | 把切片编译成可执行 goal 指令 | `npx skills add joeseesun/qiaomu-goal-meta-skill` | 按本 skill 的 `references/goal-template.md` 手写 goal 结构 |

启动时：

1. 检查推荐 skill 是否在当前会话可用；缺失则**明确告知用户**影响阶段与降级选项，由用户决定是否继续。
2. 若推荐 skill 可用，读取并遵循其正文后再执行对应阶段；不能只检查名称。
3. `grill-me` 是访谈入口，`grilling` 是访谈正文；有项目文档、ADR、SPEC 或需要边聊边落文档时，优先用 `grill-with-docs`（若存在）。
4. **goal 的权威结构以 `references/goal-template.md` 为准**。`qiaomu-goal-meta-skill` 只负责填好其中的「工具 goal 指令」段（目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件）；阶段提示词、代码锚点、DoD、验收 checklist 仍按本模板组织。

## 流程总览

```
阶段 1  grill 分析      →  .adr/<id>/plan.md（决策记录 + 切片 roadmap + 用户确认）
阶段 2  loop 小周期     →  1 goal 编译 → 2 tmux runner → 3 验收子代理（逐片循环）
收尾    最终汇总汇报    →  全部切片验收通过后，progress.md 收官条目，loop 结束
```

核心产物（全部在 `.adr/<id>/`，`<id>` 形如 `0042-add-rate-limit`）：

| 文件 | 角色 |
|---|---|
| `plan.md` | ADR 决策记录 + 切片 roadmap（**单一事实源**，状态列驱动 loop） |
| `next-goal.md` | 当前切片的自包含 goal（runner 的唯一输入） |
| `progress.md` | 巡检日志 + 切片状态表（哨兵每 tick 追加） |
| `run/launch-runner.sh` | runner 启动器（见 scripts/launch-runner-template.sh） |
| `run/<impl>-<slice>.log` | runner 全量日志（stream-json） |
| `run/<impl>-<slice>-report.md` | 每片交付报告（runner 自己写） |
| `run/<impl>-<slice>-acceptance.md` | 每片验收报告（验收子代理写，必须给出全部完成/未完成/BLOCKED） |

## 阶段 1：grill 分析 → plan.md

用 grill 族 skill（有 SPEC/ADR 文档时用 grill-with-docs，否则用 grilling）逐题深挖需求。无 grill skill 时，直接基于用户提供的设计文档填写 plan.md。grill 的产出**当场落盘**，不要等全部聊完再补记：

1. 每个裁决点解决后立即追加到 `.adr/<id>/plan.md` 的「决策」小节（编号决策，形如 ADR 决策 1/2/3…）。
2. grill 收尾时，把决策组合成**切片 roadmap**写入 plan.md，切片设计要点：
   - 每片是「一次无人值守 session 能完成的量」——经验值：一片 ≈ 15-60 分钟 runner 时长、一二十个文件改动。太大会撞上下文/限流，太小浪费点火开销。
   - 切片间**依赖单向**（后片只依赖前片的 commit），禁止环。
   - 涉及外部凭据/人工输入的片放最后并标 `paused`，到达时通知用户而不是硬跑。
   - 状态列词汇固定：`open`（当前在做，**至多一个**）/ `done (commit, 门禁数字)` / `pending` / `paused(原因)`。
3. roadmap 里写清「每片统一 DoD」：门禁命令 + 全绿标准、commit message 前缀约定、报告路径、BLOCKED 停机条件（语义歧义 / 门禁 N 轮不过 / 需外部凭据）。
4. grill 收尾必须问用户确认 plan 是否进入 loop。确认后在 plan.md 写「确认记录」：确认人/时间/确认范围/允许的 `--impl`。没有这条记录，不得进入阶段 2。

grill 完成标准：

- 所有会影响架构边界、写入范围、验收标准、凭据/人工输入、执行深度的问题都已有裁决。
- 用户已明确确认 plan 可进入 loop；沉默、默认假设、模型自行判断都不算确认。
- plan.md 里有且仅有一个 `open` 切片，其余为 `pending` 或 `paused(原因)`。

plan.md 模板见 `references/plan-template.md`。

## 阶段 2：loop 小周期

### 隔离执行区

在 git worktree 里跑，分支命名 `feat/adr<id>-<slug>`。**绝不 push**——所有 commit 留在本地，人验收后再决定合入方式。`.adr/<id>/` 目录放在 worktree 内随分支走。

进入阶段 2 前先检查 plan.md 的确认记录；缺失就回到阶段 1，不创建 runner。

### 哨兵（定时巡检）

创建一个**每 10 分钟触发的定时任务**（用当前环境可用的定时机制；选一个避开整点的分钟数，减少与他人任务撞点）。定时任务的 prompt 就是巡检指令，要求每次：

1. 一次命令汇总：tmux session 存活性、当前切片日志行数、`tail -c 2000` 提取最近动作、`git log --oneline -3`、roadmap 当前 open 切片。
2. 停滞判定：runner alive 但日志行数与上一 tick 相同 → 记「疑似停滞×N」，连续 2 次**主动通知用户**（用当前环境的通知机制；没有就在回复中显著标注）。
3. 往 `progress.md` 巡检表**追加一行**（时间/切片/runner 状态/提交数/行数+一句话要点）。
4. runner gone 且该片仍 open → 进入小周期 3 验收子代理。
5. loop 收官后删除该定时任务。

### 小周期 1：goal 编译

每片一次，委派 goal 编译子代理：

- 输入：plan.md 的该片行 + 相关 ADR 决策 + 上一片报告 + 现状代码锚点。
- **结构契约**：输出必须符合 `references/goal-template.md`（自包含 next-goal.md）。
- **工具 goal 指令段**：若 `qiaomu-goal-meta-skill` 可用，用它把切片编译为含目标、验证、约束、边界、迭代策略、完成条件、暂停条件的 goal 指令，原样写入该段；否则按 goal-template 中同名字段手写等价内容。
- 阶段提示词、代码锚点、分阶段任务、DoD、验收 checklist、BLOCKED 条件始终按 goal-template 补齐。
- ⚠️ **写入路径必须显式写绝对路径到 worktree 的 `.adr/<id>/next-goal.md`**。血泪教训：agent 曾写到主仓导致 runner 读到旧 goal 困惑退出。prompt 里把目标路径原文写出来并要求 agent 写完后自检。
- goal 编译 agent 只写 next-goal.md，不改业务代码、不提交、不点火。

完成标准：next-goal.md 已存在，包含 goal 指令、实现提示词、验收 checklist、完成条件、暂停条件、报告路径，并且没有占位符。

### 小周期 2：tmux runner 实现

首次进入小周期 2 时，从 `scripts/launch-runner-template.sh` 复制一份到 `.adr/<id>/run/launch-runner.sh`，按环境改四处：worktree 绝对路径、impl 名称、代理设置、impl 命令行。要点（都是实战踩过的坑）：

- **绝对路径**：tmux 新 session 不继承你的 shell 环境，PATH/cwd 全部显式写。
- **不走交互式 shell 别名**：形如 `run_with_proxy` 的别名内部若有 `read` 会把无人值守 session 卡死；代理 env 直接内联 export。
- **stream-json 日志 tee 落盘**：哨兵靠日志行数判进展，靠 tail 判当前动作。
- runner 的唯一任务输入是 `.adr/<id>/next-goal.md`；其中同时包含工具 goal 指令和阶段实现提示词。runner 必须原样消费该文件，不得依赖主会话上下文。

### impl 选项

用户可用 `--impl=` 指定实现子进程，默认 `claude-code`：

| impl | 启动命令核心 |
|---|---|
| `claude-code`（默认） | `claude -p --permission-mode bypassPermissions --verbose --output-format stream-json < .adr/<id>/next-goal.md` |
| `codex` | `codex exec --full-auto "$(cat .adr/<id>/next-goal.md)"`（或 `codex exec --json` 落结构化日志） |
| `grok` | `grok --prompt-file .adr/<id>/next-goal.md --permission-mode bypassPermissions --output-format streaming-json`（headless 不读 stdin，必须用 `--prompt-file`；`--yolo` / `--always-approve` 与 `bypassPermissions` 等价） |

三者的 goal 内容完全一致——goal 是自包含的，不依赖执行器。未指定 `--impl` 时一律用 `claude-code`。

### 点火

```bash
tmux new-session -d -s adr-<slice> '<worktree>/.adr/<id>/run/launch-runner.sh <slice>'
```

先尝试自己直接执行。若被权限机制拦截（bypassPermissions 启动属敏感操作，安全分类不可用时会拒），在 progress.md 记「待点火」，并给用户一条可直接 `!` 前缀执行的完整命令。权限恢复后下一 tick 可重试自动点火——两条路都保持开着。

### runner 生命周期

一片一个 tmux session（`adr-f1`、`adr-f2`…），跑完自然退出。哨兵发现 gone → 核验 → 推进。同一时间只有一个 runner 在跑（切片串行，依赖前片 commit）。

### 小周期 3：验收子代理

tmux runner 退出后，必须委派验收子代理做阶段性验收。验收子代理输入：plan.md 当前切片、next-goal.md、runner 日志、runner 报告、git diff/log、门禁输出。

验收子代理必须对抗式检查：

1. next-goal.md 的验收 checklist 是否逐项满足。
2. runner 报告是否存在，是否包含门禁数字、变更清单、偏差说明，且没有未处理的 BLOCKED。
3. commit 是否真实产生，提交范围是否只覆盖本切片。
4. 相关门禁是否真实运行且无回归；门禁数字要能从日志或报告追溯。
5. roadmap 状态是否未被 runner 擅自推进。

验收子代理写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`，结论只能是：

- `全部完成`：主会话把本片置 `done (commit, 数字)`；若还有 pending 切片，把下一片置 `open` 并回到小周期 1。
- `未完成`：指出缺口；可自动修复时，保持本片 `open`，重新进入小周期 1 编译修复 goal。
- `BLOCKED`：写清需要的人类决策/凭据/外部条件，把本片置 `paused(原因)` 并通知用户。

## 收尾

最后一片 done 后：

1. 确认每片都有 runner 报告与验收报告，且最后一份验收报告结论为 `全部完成`。
2. 对抗式全量核验：全部切片 commit 齐、门禁最终数字、报告齐、验收报告齐。
3. 在 `progress.md` 写收官条目（每片 commit/测试数/成本汇总表）。
4. 若项目有全局进展文档（如 `docs/STATUS.md`、changelog、kb progress），补一条**简短**收官记录——per-tick 日志留在 `.adr/<id>/progress.md`，不要污染全局文档。
5. 删哨兵定时任务，通知用户 loop 结束 + 待人工验收清单（如有）。

## 常见故障对照表

| 症状 | 原因 | 处置 |
|---|---|---|
| runner 退出、无报告、有未提交改动 | API 限流 / session 超时 | 直接重启 runner，续跑捡起改动 |
| runner 秒退、日志显示困惑 | next-goal.md 是旧片内容 | goal 写错路径——检查是否写进了主仓；修正后重启 |
| 自动点火被权限拦截 | 安全分类暂不可用 | 记「待点火」，给用户 `!` 命令；下一 tick 重试 |
| 日志行数连续两 tick 不涨 | runner 卡死（网络/死循环） | kill session 重启；连续发生则降低该片粒度 |
| 报告含 BLOCKED | 语义歧义 / 门禁不过 / 缺凭据 | 读报告定位：可自决的编修复 goal，需人工的置 paused 通知 |

## 参考

- `references/plan-template.md` — plan.md（决策 + roadmap）模板
- `references/goal-template.md` — next-goal.md 结构模板（本 skill 的权威契约；可选经 qiaomu 填「工具 goal 指令」段）
- `scripts/launch-runner-template.sh` — runner 启动器模板
