---
name: adr-driven-development
description: Use when the user wants an ADR-driven unattended delivery loop, asks to slice a large requirement into verified local commits, continue an existing .adr/<id>/plan.md loop, or run implementation through tmux with an --impl runner and cross-tool --reviewer adversarial acceptance.
version: 0.2.0
---

# ADR 驱动开发（grill → loop → tmux 无人值守实现）

把一个模糊的大需求变成「已核验的一串本地 commit」的完整流水线。人只在两个点介入：前期 grill 对话（裁决设计），以及 tmux 点火被权限拦截时手动执行一条命令。其余全部自动。

## 硬性执行契约

本 skill 的顺序不可重排：

1. **grill 门禁**：先深挖意图、裁决方案和实现深度，写出 plan.md，并取得用户对 plan 的明确确认。
2. **loop 小周期**：只在 plan 已确认后，按「goal 编译 → tmux runner → 跨工具验收 reviewer」串行推进切片。
3. **最终汇总**：只有验收 reviewer 汇报全部完成后，才能进入最终汇总汇报。

禁止项：

- **禁止跳过 grill 直接实现**。只有两种例外：用户明确说已有设计可跳过 grill，或 `.adr/<id>/plan.md` 已存在且包含已确认的「决策 + roadmap + DoD」。例外也要在 progress.md 记下原因。
- **禁止主会话内联实现切片代码**。主会话只做 grill、plan/goal 编排、runner 点火、巡检、核验和报告；业务代码变更必须由 tmux runner 完成。若 tmux 不可用或点火被拦截，记录为 `paused(待点火)` 并通知用户，不自动退化为内联实现。
- **禁止把 runner 自报完成当成完成**。runner 退出后必须委派**验收 reviewer**（默认与 impl **不同**的 agent 工具）做对抗式检查；没有验收 reviewer 的「全部完成」结论，就不能把下一片置为 open，也不能进入最终汇总。
- **禁止默认同工具自检冒充对抗验收**。未显式指定 `--reviewer=` 时，必须按下方默认配对表选择与 `--impl` 不同的工具；仅当用户明确允许，或环境里只剩一个可用工具时，才可同工具验收，并在 progress.md / 确认记录写明原因。

## 可选依赖（开源安装）

本 skill **可独立使用**：`references/plan-template.md` 与 `references/goal-template.md` 已给出完整落盘结构。下列 skill 为推荐增强，缺失时走降级路径，不阻塞启动。

| 阶段 | 推荐 skill | 作用 | 安装（示例） | 缺失时降级 |
|---|---|---|---|---|
| 阶段 1 | `grill-me` / `grilling` / `grill-with-docs`（[mattpocock/skills](https://github.com/mattpocock/skills)） | 需求深挖访谈 | `npx skills add mattpocock/skills`（或 `skills add mattpocock/skills`） | 用户提供现成设计/ADR/SPEC，或主会话按 plan-template 做轻量访谈 |
| 小周期 1 | [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT） | 把切片编译成可执行 goal 指令 | `npx skills add joeseesun/qiaomu-goal-meta-skill` | 按本 skill 的 `references/goal-template.md` 手写 goal 结构 |

### 启动时依赖检查（必须做）

1. **检查 grilling 系列是否可用**：在当前 agent 的 skills 目录 / 会话已加载 skill 中查找 `grill-me`、`grilling`、`grill-with-docs`（任一存在即可）。
2. **若全部缺失 → 主动询问用户，不得静默降级**：
   - 说明影响：缺少深度访谈 skill，阶段 1 的设计裁决质量会下降。
   - 给出明确选项（用当前环境的提问机制；没有则直接文字列出让用户选）：
     1. **安装（推荐）**：执行 `npx skills add mattpocock/skills`（若本机已装 skills CLI，等价于 `skills add mattpocock/skills`）。可选加 `-y -g` 做全局非交互安装。装完后重新加载/确认 skill 可用，再进入 grill。
     2. **跳过安装，用现成设计**：用户提供 ADR/SPEC/设计文档，主会话按 plan-template 直接落 plan.md。
     3. **跳过安装，轻量访谈**：主会话按 plan-template 的决策/roadmap 结构自行提问（不调用 grill skill）。
   - 用户同意安装时：给出可复制命令并等待安装完成（或代为执行若环境允许）；**不要**在用户拒绝前擅自 `npx skills add`。
   - 将用户选择与命令原文记入 progress.md（或启动笔记），便于复盘。
3. 若推荐 skill 可用，**读取并遵循其正文**后再执行对应阶段；不能只检查名称。
4. `grill-me` 是访谈入口，`grilling` 是访谈正文；有项目文档、ADR、SPEC 或需要边聊边落文档时，优先用 `grill-with-docs`（若存在）。
5. **goal 的权威结构以 `references/goal-template.md` 为准**。`qiaomu-goal-meta-skill` 只负责填好其中的「工具 goal 指令」段（目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件）；阶段提示词、代码锚点、DoD、验收 checklist 仍按本模板组织。
6. 同步检查 `qiaomu-goal-meta-skill`：缺失时告知可装与降级路径，**不强制**询问安装（goal 模板已足够自洽）；用户主动要装再用 `npx skills add joeseesun/qiaomu-goal-meta-skill`。

## 流程总览

```
阶段 1  grill 分析      →  .adr/<id>/plan.md（决策记录 + 切片 roadmap + 用户确认）
阶段 2  loop 小周期     →  1 goal 编译 → 2 tmux impl runner → 3 跨工具 reviewer 对抗验收（逐片循环）
收尾    最终汇总汇报    →  全部切片验收通过后，progress.md 收官条目，loop 结束
```

核心产物（全部在 `.adr/<id>/`，`<id>` 形如 `0042-add-rate-limit`）：

| 文件 | 角色 |
|---|---|
| `plan.md` | ADR 决策记录 + 切片 roadmap（**单一事实源**，状态列驱动 loop；含 impl/reviewer 确认） |
| `next-goal.md` | 当前切片的自包含 goal（impl runner 的唯一输入） |
| `progress.md` | 巡检日志 + 切片状态表（哨兵每 tick 追加） |
| `run/launch-runner.sh` | impl runner 启动器（见 scripts/launch-runner-template.sh） |
| `run/<impl>-<slice>.log` | impl runner 全量日志（stream-json） |
| `run/<impl>-<slice>-report.md` | 每片交付报告（impl runner 自己写） |
| `run/<impl>-<slice>-acceptance-prompt.md` | 验收 prompt（主会话写，reviewer 唯一输入） |
| `run/<reviewer>-<slice>-acceptance.log` | reviewer 运行日志 |
| `run/<impl>-<slice>-acceptance.md` | 每片验收报告（reviewer 写，必须给出全部完成/未完成/BLOCKED，并注明 impl/reviewer） |

## 阶段 1：grill 分析 → plan.md

**进入本阶段前**先完成「启动时依赖检查」。若 grilling 系列未安装，必须先询问是否 `npx skills add mattpocock/skills`，不得静默跳过。

用 grill 族 skill（有 SPEC/ADR 文档时用 `grill-with-docs`，否则用 `grill-me` / `grilling`）逐题深挖需求。用户选择跳过安装时，按所选降级路径（现成设计或轻量访谈）填写 plan.md。grill 的产出**当场落盘**，不要等全部聊完再补记：

1. 每个裁决点解决后立即追加到 `.adr/<id>/plan.md` 的「决策」小节（编号决策，形如 ADR 决策 1/2/3…）。
2. grill 收尾时，把决策组合成**切片 roadmap**写入 plan.md，切片设计要点：
   - 每片是「一次无人值守 session 能完成的量」——经验值：一片 ≈ 15-60 分钟 runner 时长、一二十个文件改动。太大会撞上下文/限流，太小浪费点火开销。
   - 切片间**依赖单向**（后片只依赖前片的 commit），禁止环。
   - 涉及外部凭据/人工输入的片放最后并标 `paused`，到达时通知用户而不是硬跑。
   - 状态列词汇固定：`open`（当前在做，**至多一个**）/ `done (commit, 门禁数字)` / `pending` / `paused(原因)`。
3. roadmap 里写清「每片统一 DoD」：门禁命令 + 全绿标准、commit message 前缀约定、报告路径、BLOCKED 停机条件（语义歧义 / 门禁 N 轮不过 / 需外部凭据）。
4. grill 收尾必须问用户确认 plan 是否进入 loop。确认后在 plan.md 写「确认记录」：确认人/时间/确认范围/允许的 `--impl` 与 `--reviewer`（可写「按默认配对」）。没有这条记录，不得进入阶段 2。

grill 完成标准：

- 所有会影响架构边界、写入范围、验收标准、凭据/人工输入、执行深度的问题都已有裁决。
- 用户已明确确认 plan 可进入 loop；沉默、默认假设、模型自行判断都不算确认。
- plan.md 里有且仅有一个 `open` 切片，其余为 `pending` 或 `paused(原因)`。
- 确认记录中已锁定 impl / reviewer（或「按默认配对」的明确字样）。

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
4. runner gone 且该片仍 open → 进入小周期 3 跨工具 reviewer 对抗验收。
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

### impl 与 reviewer 选项

用户可用 `--impl=` 指定实现子进程，用 `--reviewer=` 指定对抗验收工具。未指定时：

- **impl 默认**：`claude-code`
- **reviewer 默认**：与 impl **不同** 的 agent（见配对表）；对抗检查的核心价值就是「换一双眼睛」

| 工具 | 角色可用 | 启动命令核心（输入文件不同：impl 读 next-goal.md，reviewer 读 acceptance-prompt.md） |
|---|---|---|
| `claude-code` | impl / reviewer | `claude -p --permission-mode bypassPermissions --verbose --output-format stream-json < <input>` |
| `codex` | impl / reviewer | `codex exec --full-auto "$(cat <input>)"`（或 `codex exec --json` 落结构化日志） |
| `grok` | impl / reviewer | `grok --prompt-file <input> --permission-mode bypassPermissions --output-format streaming-json`（headless 不读 stdin，必须用 `--prompt-file`；`--yolo` / `--always-approve` 与 `bypassPermissions` 等价） |

三者的 goal / 验收 prompt 内容完全一致——产物是自包含的，不依赖执行器。

#### 默认 reviewer 配对（`--reviewer` 未指定时强制应用）

| impl | 默认 reviewer（按优先级，取本机**已安装且可执行**的第一个） |
|---|---|
| `claude-code` | `codex` → `grok` |
| `codex` | `claude-code` → `grok` |
| `grok` | `claude-code` → `codex` |

示例：`impl=claude-code` 且本机有 codex → reviewer 用 `codex`；没有 codex 但有 grok → reviewer 用 `grok`。

解析规则：

1. 用户显式 `--reviewer=X`：用 X；若 `X == impl`，**警告**并请用户确认「同工具自检」是否可接受；未确认则改回默认配对。
2. 用户未指定：按上表选与 impl 不同的工具。
3. 表中候选均不可用：告知用户缺失情况，请其安装另一工具或明确授权同工具验收；**不得**静默同工具验收。
4. 将最终 `impl` / `reviewer` 写入 plan.md 确认记录与 progress.md 启动行。

### 点火

```bash
tmux new-session -d -s adr-<slice> '<worktree>/.adr/<id>/run/launch-runner.sh <slice>'
```

先尝试自己直接执行。若被权限机制拦截（bypassPermissions 启动属敏感操作，安全分类不可用时会拒），在 progress.md 记「待点火」，并给用户一条可直接 `!` 前缀执行的完整命令。权限恢复后下一 tick 可重试自动点火——两条路都保持开着。

### runner 生命周期

一片一个 tmux session（`adr-f1`、`adr-f2`…），跑完自然退出。哨兵发现 gone → 核验 → 推进。同一时间只有一个 runner 在跑（切片串行，依赖前片 commit）。

### 小周期 3：跨工具对抗验收（reviewer）

tmux runner 退出后，必须启动 **reviewer**（默认 ≠ impl）做阶段性对抗验收。主会话**不得**仅凭自身通读 diff 就代替 reviewer 下「全部完成」结论。

#### 启动前

1. 解析本 loop 的 `impl` / `reviewer`（确认记录 > CLI 参数 > 默认配对）。
2. 主会话写自包含验收 prompt 到 worktree 绝对路径：
   `.adr/<id>/run/<impl>-<slice>-acceptance-prompt.md`
   内容须包含：plan.md 当前切片原文、next-goal.md 路径、runner 日志路径、runner 报告路径、建议的 `git log` / `git diff` 范围、门禁命令、**验收报告输出绝对路径**、对抗检查清单（见下）、结论只能三选一。
3. 用 reviewer 对应 CLI 启动（可 tmux session `adr-<slice>-review`，或 headless 一次性进程）。日志 tee 到：
   `.adr/<id>/run/<reviewer>-<slice>-acceptance.log`

reviewer 启动命令示例（`<PROMPT>` = acceptance-prompt 绝对路径）：

| reviewer | 命令骨架 |
|---|---|
| `claude-code` | `claude -p --permission-mode bypassPermissions --verbose --output-format stream-json < "$PROMPT"` |
| `codex` | `codex exec --full-auto "$(cat "$PROMPT")"` |
| `grok` | `grok --prompt-file "$PROMPT" --permission-mode bypassPermissions --output-format streaming-json` |

#### 对抗检查清单（写入 prompt，reviewer 必须逐项给证据）

1. next-goal.md 的验收 checklist 是否逐项满足。
2. runner 报告是否存在，是否包含门禁数字、变更清单、偏差说明，且没有未处理的 BLOCKED。
3. commit 是否真实产生，提交范围是否只覆盖本切片。
4. 相关门禁是否真实运行且无回归；门禁数字要能从日志或报告追溯。
5. roadmap 状态是否未被 runner 擅自推进。
6. （对抗加码）主动寻找：遗漏边界、测试未覆盖路径、与 ADR 决策冲突、虚假门禁（报告数字与日志不符）。

#### 验收产出

reviewer 写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`（文件头注明 `impl=` / `reviewer=`），结论只能是：

- `全部完成`：主会话把本片置 `done (commit, 数字)`；若还有 pending 切片，把下一片置 `open` 并回到小周期 1。
- `未完成`：指出缺口；可自动修复时，保持本片 `open`，重新进入小周期 1 编译修复 goal。
- `BLOCKED`：写清需要的人类决策/凭据/外部条件，把本片置 `paused(原因)` 并通知用户。

reviewer 只写验收报告与（可选）复跑门禁；**不改业务代码、不 commit、不推进 roadmap**。状态推进仍由主会话根据验收结论执行。

## 收尾

最后一片 done 后：

1. 确认每片都有 impl runner 报告与 reviewer 验收报告，且最后一份验收报告结论为 `全部完成`；验收报告头应写明 `impl` / `reviewer`。
2. 对抗式全量核验（仍优先用与 impl 不同的 reviewer 工具，或主会话在 reviewer 报告基础上做二次核对）：全部切片 commit 齐、门禁最终数字、报告齐、验收报告齐。
3. 在 `progress.md` 写收官条目（每片 commit/测试数/impl/reviewer/成本汇总表）。
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
| grilling skill 找不到 | 未装 mattpocock/skills | **询问**是否 `npx skills add mattpocock/skills`；拒绝则走现成设计/轻量访谈 |
| 验收被主会话直接放行 | 未启动跨工具 reviewer | 补写 acceptance-prompt 并用默认配对启动 reviewer；同工具须用户书面确认 |
| reviewer CLI 不存在 | 默认配对候选均未安装 | 告知缺失，请安装另一 agent 或授权同工具验收；不得静默同工具 |

## 参考

- `references/plan-template.md` — plan.md（决策 + roadmap）模板
- `references/goal-template.md` — next-goal.md 结构模板（本 skill 的权威契约；可选经 qiaomu 填「工具 goal 指令」段）
- `scripts/launch-runner-template.sh` — impl runner 启动器模板
