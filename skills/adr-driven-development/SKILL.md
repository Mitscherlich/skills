---
name: adr-driven-development
description: Use when the user wants an ADR-driven unattended delivery loop, asks to slice a large requirement into verified local commits, continue an existing .adr/<id>/plan.md loop, or run implementation through tmux or Orca (orca-cli worktree + impl/reviewer agent fan-out) with --impl and cross-tool --reviewer adversarial acceptance.
version: 0.3.1
---

# ADR 驱动开发（grill → loop → host runner 无人值守实现）

把一个模糊的大需求变成「已核验的一串本地 commit」的完整流水线。人只在两个点介入：前期 grill 对话（裁决设计），以及 runner 点火被权限拦截时手动执行一条命令。其余全部自动。

**执行宿主（host）**：进入 loop 时**必须**跑 `scripts/detect-runtime-host.sh` 拿结果，**禁止**靠读文档/环境变量自行推理 host（浪费 token 且易漂）。默认倾向 `tmux`；脚本在 Orca 环境且 CLI 健康时返回 `orca`。可用 `--host=` / `ADR_HOST=` / 脚本 `--force` 覆盖。

## 硬性执行契约

本 skill 的顺序不可重排：

1. **grill 门禁**：先深挖意图、裁决方案和实现深度，写出 plan.md，并取得用户对 plan 的明确确认。
2. **loop 小周期**：只在 plan 已确认后，按「host 解析 → goal 编译 → impl runner → 跨工具验收 reviewer」串行推进切片。
3. **最终汇总**：只有验收 reviewer 汇报全部完成后，才能进入最终汇总汇报。

禁止项：

- **禁止跳过 grill 直接实现**。只有两种例外：用户明确说已有设计可跳过 grill，或 `.adr/<id>/plan.md` 已存在且包含已确认的「决策 + roadmap + DoD」。例外也要在 progress.md 记下原因。
- **禁止主会话内联实现切片代码**。主会话只做 grill、plan/goal 编排、host 解析、runner 点火、巡检、核验和报告；业务代码变更必须由 **host 上的 impl runner**（tmux session 或 Orca agent terminal）完成。若 host 点火失败，记录为 `paused(待点火)` 并通知用户，**不**自动退化为内联实现；Orca 探测失败可降级 `host=tmux`，仍不得内联。
- **禁止把 runner 自报完成当成完成**。impl 退出后必须委派**验收 reviewer**（默认与 impl **不同**的 agent 工具）做对抗式检查；没有验收 reviewer 的「全部完成」结论，就不能把下一片置为 open，也不能进入最终汇总。
- **禁止默认同工具自检冒充对抗验收**。未显式指定 `--reviewer=` 时，必须按下方默认配对表选择与 `--impl` 不同的工具；仅当用户明确允许，或环境里只剩一个可用工具时，才可同工具验收，并在 progress.md / 确认记录写明原因。

## 可选依赖（开源安装）

本 skill **可独立使用**：`references/plan-template.md` 与 `references/goal-template.md` 已给出完整落盘结构。下列 skill 为推荐增强，缺失时走降级路径，不阻塞启动。

| 阶段 | 推荐 skill / 工具 | 作用 | 安装（示例） | 缺失时降级 |
|---|---|---|---|---|
| 阶段 1 | `grill-me` / `grilling` / `grill-with-docs`（[mattpocock/skills](https://github.com/mattpocock/skills)） | 需求深挖访谈 | `npx skills add mattpocock/skills`（或 `skills add mattpocock/skills`） | 用户提供现成设计/ADR/SPEC，或主会话按 plan-template 做轻量访谈 |
| 小周期 1 | [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT） | 把切片编译成可执行 goal 指令 | `npx skills add joeseesun/qiaomu-goal-meta-skill` | 按本 skill 的 `references/goal-template.md` 手写 goal 结构 |
| host=orca | `orca-cli` skill + 本机 `orca` CLI | worktree / terminal 扇出 impl·reviewer | Orca 应用自带 CLI；会话内 `ORCA skills get orca-cli` | 降级 `host=tmux` + `scripts/launch-runner-template.sh` |

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
阶段 2  loop 小周期     →  0 解析 host（tmux|orca）→ 1 goal 编译 → 2 impl runner → 3 跨工具 reviewer（逐片循环）
收尾    最终汇总汇报    →  全部切片验收通过后，progress.md 收官条目，loop 结束
```

| host | 隔离执行区 | impl | reviewer |
|---|---|---|---|
| `tmux`（默认） | `git worktree` + `launch-runner.sh` | tmux session 跑 headless CLI | tmux/headless 另一进程 |
| `orca`（Orca 环境自动） | `orca worktree create` | 同 worktree 内 `terminal create --command <agent>` | **同一 worktree** 另一 agent terminal |

核心产物（全部在 `.adr/<id>/`，`<id>` 形如 `0042-add-rate-limit`）：

| 文件 | 角色 |
|---|---|
| `plan.md` | ADR 决策记录 + 切片 roadmap（**单一事实源**；含 host / impl / reviewer 确认） |
| `next-goal.md` | 当前切片的自包含 goal（impl runner 的唯一输入） |
| `progress.md` | 巡检日志 + 切片状态表 + host/worktree/handle 记录 |
| `run/launch-runner.sh` | **仅 host=tmux**：impl 启动器（见 scripts/launch-runner-template.sh） |
| `run/<impl>-<slice>.log` | impl 日志（tmux: stream-json；orca: terminal read 摘要亦可） |
| `run/<impl>-<slice>-report.md` | 每片交付报告（impl 写） |
| `run/<impl>-<slice>-acceptance-prompt.md` | 验收 prompt（主会话写，reviewer 唯一输入） |
| `run/<reviewer>-<slice>-acceptance.log` | reviewer 运行日志 / 摘要 |
| `run/<impl>-<slice>-acceptance.md` | 每片验收报告（reviewer 写，全部完成/未完成/BLOCKED + impl/reviewer 头） |

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
4. grill 收尾必须问用户确认 plan 是否进入 loop。确认后在 plan.md 写「确认记录」：确认人/时间/确认范围/允许的 `--impl` 与 `--reviewer`（可写「按默认配对」）/ `--host`（可写「自动探测」）。没有这条记录，不得进入阶段 2。

grill 完成标准：

- 所有会影响架构边界、写入范围、验收标准、凭据/人工输入、执行深度的问题都已有裁决。
- 用户已明确确认 plan 可进入 loop；沉默、默认假设、模型自行判断都不算确认。
- plan.md 里有且仅有一个 `open` 切片，其余为 `pending` 或 `paused(原因)`。
- 确认记录中已锁定 impl / reviewer（或「按默认配对」的明确字样）。

plan.md 模板见 `references/plan-template.md`。

## 阶段 2：loop 小周期

进入阶段 2 前先检查 plan.md 的确认记录；缺失就回到阶段 1，不创建 runner。

### 0. 解析执行宿主 host（进入 loop 时必做）

**唯一权威入口**：跑 skill 内脚本，消费其 stdout，不要手写探测逻辑。

```bash
# 自动（推荐）
<path-to-skill>/scripts/detect-runtime-host.sh
# 用户指定 --host=orca|tmux 时：
<path-to-skill>/scripts/detect-runtime-host.sh --force orca   # 或 tmux
# 机器可读：
<path-to-skill>/scripts/detect-runtime-host.sh --json
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

1. `--force` / 环境变量 `ADR_HOST` / 用户 `--host=`
2. 自动：Orca 信号 + CLI `status` 健康 → `orca`，否则 `tmux`
3. 想要 orca 但 CLI 挂了 → 脚本自动降级 `tmux` 并写 `reason`

| 退出码 | 含义 |
|---|---|
| 0 | 选出的 host 可跑 |
| 1 | 不可跑（如 force orca 但 CLI 挂、或 tmux 不在 PATH）→ progress 记 `paused`/降级说明，**不得内联实现** |
| 2 | 参数错误 |

将 `host`、`orca_cli`（若有）、`reason`、impl/reviewer 原样写入 plan 确认记录与 progress 启动行。
`host=orca` 时的 worktree/terminal 扇出步骤仍见 `references/orca-host.md`（**只在 host 已定为 orca 后**再读，避免无谓烧 token）。

### 隔离执行区

- **host=tmux**：`git worktree add`，分支 `feat/adr<id>-<slug>`。
- **host=orca**：`ORCA worktree create --name adr-<id>-<slug> ...`（优先 `--parent-worktree active`），**一次 ADR 一个 Orca worktree**；impl 与 reviewer **共用该 checkout**（禁止为 reviewer 再开平行 worktree 导致看不到 impl commit）。

`.adr/<id>/` 放在 worktree 内随分支走。**绝不 push**。

Orca 详细命令与扇出步骤见 `references/orca-host.md`；操作前应 `ORCA skills get orca-cli` 核对当前 CLI 语法。

### 哨兵（定时巡检）

创建一个**每 10 分钟触发的定时任务**（用当前环境可用的定时机制；选一个避开整点的分钟数，减少与他人任务撞点）。定时任务的 prompt 就是巡检指令，要求每次：

1. 一次命令汇总：
   - **tmux**：session 存活性、日志行数、`tail -c 2000`、`git log --oneline -3`、open 切片
   - **orca**：`terminal list` / `terminal read`、报告文件是否出现、`git log --oneline -3`（在 ADR worktree path）、open 切片
2. 停滞判定：runner/agent 仍在但日志或文件无进展 → 记「疑似停滞×N」，连续 2 次**主动通知用户**。
3. 往 `progress.md` 巡检表**追加一行**（时间/切片/host/runner 状态/提交数/要点）。
4. impl 完成（报告齐）且该片仍 open → 进入小周期 3 跨工具 reviewer。
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

### 小周期 2：impl runner 实现

runner 的唯一任务输入是 `.adr/<id>/next-goal.md`（工具 goal 指令 + 阶段提示词）；必须原样消费，不得依赖主会话上下文。

#### host=tmux

首次进入小周期 2 时，从 `scripts/launch-runner-template.sh` 复制到 `.adr/<id>/run/launch-runner.sh`，改 worktree 绝对路径、impl 名称、代理、impl 命令行：

- **绝对路径**：tmux 新 session 不继承 shell；PATH/cwd 显式写。
- **不走交互式别名**：含 `read` 的代理别名会卡死无人值守 session。
- **stream-json 日志 tee 落盘**：哨兵靠行数与 tail 判进展。

点火：

```bash
tmux new-session -d -s adr-<slice> '<worktree>/.adr/<id>/run/launch-runner.sh <slice>'
```

被权限拦截时 progress 记「待点火」，给用户可 `!` 执行的完整命令；下一 tick 可重试。

一片一个 tmux session（`adr-f1`…）。同一时间只有一个 impl 在跑。

#### host=orca（扇出 impl agent）

细节见 `references/orca-host.md`。摘要：

1. 确保 ADR Orca worktree 已存在，记录 `worktree.id` = `<repoId>::<path>`。
2. 在该 worktree 扇出 **impl** terminal（agent 映射：`claude-code`→`claude`，`codex`→`codex`，`grok`→`grok`）：

```text
ORCA terminal create --worktree id:<repoId>::<path> --title adr-<slice>-impl --command <impl_orca_agent> --json
ORCA terminal wait --terminal <impl_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <impl_handle> --text "Read and execute <ABS>/.adr/<id>/next-goal.md; write report to <ABS>/.adr/<id>/run/<impl>-<slice>-report.md; local commit only; never push; do not edit plan.md status." --enter --json
```

3. **完成判定以文件哨兵为准**：存在 `run/<impl>-<slice>-report.md` 且有本片 commit；不要只听 agent 口述。
4. progress 记录 `impl_handle`；handle 失效时用 `terminal list` 重取，禁止双发。
5. 可选：`worktree set --workspace-status in-progress` / `--comment "…"`。

### impl 与 reviewer 选项

用户可用 `--impl=` / `--reviewer=` / `--host=`。未指定时：

- **host**：以 `scripts/detect-runtime-host.sh` 输出为准（勿手推）
- **impl 默认**：`claude-code`
- **reviewer 默认**：与 impl **不同** 的 agent（见配对表）

| 工具 | Orca agent id | host=tmux 启动核心（impl 读 next-goal；reviewer 读 acceptance-prompt） |
|---|---|---|
| `claude-code` | `claude` | `claude -p --permission-mode bypassPermissions --verbose --output-format stream-json < <input>` |
| `codex` | `codex` | `codex exec --full-auto "$(cat <input>)"`（或 `--json`） |
| `grok` | `grok` | `grok --prompt-file <input> --permission-mode bypassPermissions --output-format streaming-json` |

goal / 验收 prompt 内容与 host 无关——产物自包含。

#### 默认 reviewer 配对（`--reviewer` 未指定时强制应用）

| impl | 默认 reviewer（按优先级，取本机**已安装且可执行**的第一个） |
|---|---|
| `claude-code` | `codex` → `grok` |
| `codex` | `claude-code` → `grok` |
| `grok` | `claude-code` → `codex` |

示例：`impl=claude-code` → reviewer 优先 `codex` 或 `grok`（Orca 下即 `codex` / `grok` terminal）。

解析规则：

1. 用户显式 `--reviewer=X`：用 X；若 `X == impl`，**警告**并请确认；未确认则改回默认配对。
2. 用户未指定：按上表选与 impl 不同的工具。
3. 候选均不可用：告知用户；**不得**静默同工具验收。
4. 将最终 `host` / `impl` / `reviewer` 写入 plan 确认记录与 progress。

### 小周期 3：跨工具对抗验收（reviewer）

impl 完成后，必须启动 **reviewer**（默认 ≠ impl）。主会话**不得**仅凭自身通读 diff 代替 reviewer 下「全部完成」。

#### 启动前

1. 解析 `impl` / `reviewer` / `host`。
2. 主会话写自包含验收 prompt 到 worktree 绝对路径：
   `.adr/<id>/run/<impl>-<slice>-acceptance-prompt.md`
   （含切片原文、路径、git 范围、门禁、验收报告输出路径、对抗清单、结论三选一）。
3. 按 host 启动 reviewer：

**host=tmux** — headless / tmux session，日志 tee 到 `run/<reviewer>-<slice>-acceptance.log`：

| reviewer | 命令骨架 |
|---|---|
| `claude-code` | `claude -p --permission-mode bypassPermissions --verbose --output-format stream-json < "$PROMPT"` |
| `codex` | `codex exec --full-auto "$(cat "$PROMPT")"` |
| `grok` | `grok --prompt-file "$PROMPT" --permission-mode bypassPermissions --output-format streaming-json` |

**host=orca** — **同一 ADR worktree** 再扇出 reviewer terminal（agent id 用映射表）：

```text
ORCA terminal create --worktree id:<repoId>::<path> --title adr-<slice>-review --command <reviewer_orca_agent> --json
ORCA terminal wait --terminal <review_handle> --for tui-idle --timeout-ms 60000 --json
ORCA terminal send --terminal <review_handle> --text "Execute acceptance prompt at <ABS>/...-acceptance-prompt.md; write ONLY <ABS>/...-acceptance.md (impl=/reviewer= header; 全部完成|未完成|BLOCKED). No code changes, no commit, no plan.md status edits." --enter --json
```

完成判定：acceptance 文件存在且结论合法。可选 `workspace-status in-review`。

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

1. 确认每片都有 impl runner 报告与 reviewer 验收报告，且最后一份验收报告结论为 `全部完成`；验收报告头应写明 `impl` / `reviewer`（及 host 若适用）。
2. 对抗式全量核验（仍优先用与 impl 不同的 reviewer，或主会话在 reviewer 报告上二次核对）：全部切片 commit 齐、门禁最终数字、报告齐、验收报告齐。
3. 在 `progress.md` 写收官条目（每片 commit/测试数/host/impl/reviewer/成本汇总表）。
4. 若项目有全局进展文档（如 `docs/STATUS.md`、changelog、kb progress），补一条**简短**收官记录——per-tick 日志留在 `.adr/<id>/progress.md`，不要污染全局文档。
5. 删哨兵定时任务；host=orca 时可 `worktree set --workspace-status completed` 并更新 comment。
6. 通知用户 loop 结束 + 待人工验收清单（如有）。**不要**未经用户同意 `worktree rm` 删掉 ADR worktree。

## 常见故障对照表

| 症状 | 原因 | 处置 |
|---|---|---|
| runner 退出、无报告、有未提交改动 | API 限流 / session 超时 | 重启 impl（tmux 或 orca terminal），续跑捡起改动 |
| runner 秒退、日志显示困惑 | next-goal.md 是旧片内容 | goal 写错路径——检查是否写进了主仓；修正后重启 |
| 自动点火被权限拦截 | 安全分类暂不可用 | 记「待点火」，给用户 `!` 命令；下一 tick 重试 |
| 日志/终端连续两 tick 无进展 | runner 卡死 | tmux: kill 重启；orca: terminal stop/create 重扇出；多次则拆片 |
| 报告含 BLOCKED | 语义歧义 / 门禁不过 / 缺凭据 | 读报告定位：可自决的编修复 goal，需人工的置 paused 通知 |
| grilling skill 找不到 | 未装 mattpocock/skills | **询问**是否 `npx skills add mattpocock/skills`；拒绝则走现成设计/轻量访谈 |
| 验收被主会话直接放行 | 未启动跨工具 reviewer | 补写 acceptance-prompt 并按 host 启动 reviewer；同工具须用户书面确认 |
| reviewer CLI / agent 不存在 | 配对候选均未安装 | 告知缺失；不得静默同工具 |
| 探测到 Orca 但 worktree/terminal 失败 | CLI 旧 / app 未就绪 | `ORCA open` + `skills get orca-cli`；重跑 `detect-runtime-host.sh`，失败则 tmux |
| reviewer 看不到 impl commit | 误开了第二个 worktree | 强制同一 `worktree.id`；废掉平行树后重跑验收 |
| `terminal_handle_stale` | Orca 重启或 handle 过期 | `terminal list` 取新 handle，只对新 handle send |
| agent 自行猜 host 与脚本不一致 | 未跑 detect 脚本 | **以脚本 stdout 为准**；重跑并覆盖 plan/progress |

## 参考

- `references/plan-template.md` — plan.md（决策 + roadmap）模板
- `references/goal-template.md` — next-goal.md 结构模板（本 skill 的权威契约；可选经 qiaomu 填「工具 goal 指令」段）
- `references/orca-host.md` — host=orca 时 orca-cli worktree / impl·reviewer 扇出手册（**host 已定为 orca 后再读**）
- `scripts/detect-runtime-host.sh` — **host 探测唯一入口**（进入 loop 必跑）
- `scripts/launch-runner-template.sh` — host=tmux 时 impl runner 启动器模板
