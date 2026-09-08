# devloop 执行协议（进入 loop 后读取）

进入执行前运行 intent/spec/plan 三个正式门禁并核对真实确认来源；`--draft` 不能授权点火。协调者不内联业务实现，保持 host runner 与独立 reviewer 的职责隔离。

默认只做本地提交。用户另行授权发布时，完成本轮验收后按 [收尾协议](closeout.md) 对接项目发布流程。

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
`host=orca` 时的 worktree/terminal 扇出步骤见 [Orca 执行规程](orca-host.md)（**只在 host 已定为 orca 后**再读，避免无谓烧 token）。

### 0.5 解析哨兵调度（进入 loop 时必做）

host 定下来之后、创建哨兵之前，**必须**跑调度探测。协调者（主会话 harness）和 impl/reviewer 不是一回事。`loop_supported=1` 只认**间隔调度** `/loop`（`/loop 10m <tick>` = 每 10 分钟再跑）。Claude Code / Grok 是这种。OMP 18.1+ 虽有同名 `/loop`，但是 yield 后立刻重投（`/loop 10m` = 连续重投最多 10 分钟），**不能当哨兵**；Orca 里用 omp 当协调者时走 `orca-automation`。

```bash
<path-to-skill>/scripts/devloop detect-scheduler
<path-to-skill>/scripts/devloop detect-scheduler --json
```

| 字段 | 含义 |
|---|---|
| `coordinator` | `claude-code` / `codex` / `grok` / `omp` / `pi` / `unknown` |
| `loop_supported` | `1` 才能用间隔 `/loop`；仅 `claude-code` / `codex` / `grok`。omp 的 yield `/loop` 不算 |
| `orca_env` | `1` = 当前在 Orca |
| `scheduler` | `loop` / `orca-automation` / `cron` / `ask` — **直接采用，勿再推理** |
| `reason` | 写入 progress.md |

| 退出码 | 含义 |
|---|---|
| 0 | 调度已决定（`loop` / `orca-automation` / `cron`） |
| 1 | `scheduler=ask`：必须停下来问用户 |
| 2 | 参数错误 |

按 `scheduler=` 执行（禁止自己改判）：

- **`loop`**：当前协调者支持间隔 `/loop`，直接建每 10 分钟的 `/loop`（避开整点分钟）。
- **`orca-automation`**：协调者没有间隔 `/loop`，但人在 Orca。**自动**用 Orca automations 当哨兵，并**告知用户**：当前协调者是 `<coordinator>`，没有间隔 `/loop`（omp 的 yield `/loop` 不能当 10 分钟哨兵），已改用 Orca automation，不必换 agent。不要再问「cron 还是换人」，也不要另建 crontab。
  - `ORCA automations create --name devloop-<id>-sentinel --trigger "<避开整点的 10 分钟 cron>" --workspace active --reuse-session --prompt "<tick prompt>" --json`
  - `--reuse-session` 打回当前协调者会话；`--provider` 以 `ORCA automations create --help` 为准，不要另开第二个协调者。
  - 把 automation id 写入 progress / plan 确认记录。
- **`ask`**：不支持间隔 `/loop`，也不在 Orca。用提问通道告诉用户当前协调者不能用间隔 `/loop` 当哨兵，请选：本机 cronjob / launchd，或换 claude-code / codex / grok 再进 loop。未选之前 progress 记 `paused(待选哨兵调度)`，不创建 cron、不点火。
- 用户已书面选定后才用 `--force loop|cron|orca-automation`。`--force loop` 在 `loop_supported=0` 时仍会 `ask`。

### 隔离执行区

- **host=tmux**：`git worktree add`，分支 `feat/devloop-<id>-<slug>`。
- **host=orca**：`ORCA worktree create --name devloop-<id>-<slug> ...`（优先 `--parent-worktree active`），**一个 devloop 一个 Orca worktree**；impl 与 reviewer **共用该 checkout**（禁止为 reviewer 再开平行 worktree 导致看不到 impl commit）。plan 必须记录 `setup=run|skip|inherit`。

完成 lifecycle 交接后，在执行 worktree 立刻运行 `git config remote.origin.pushurl no_push`（或等价的无效 push URL）做硬禁 push，并验证配置生效。`.devloop/<id>/` 是本地执行记录，检查 Git 排除规则已生效；业务提交只暂存 allowlist 内路径。

Orca 详细命令与扇出步骤见 [Orca 执行规程](orca-host.md)；操作前应 `ORCA skills get orca-cli` 核对当前 CLI 语法。

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

- 输入：spec.md 中本片覆盖的 `R<n>` 原文 + plan.md 的该片行与统一 DoD + 相关裁决 `I-<n>` + 上一片报告 + 现状代码锚点。按 [知识维护协议](knowledge.md) 读取本片相关知识并将路径与约束带入 goal。
- **结构契约**：输出必须符合 `../templates/next-goal.md`（自包含 next-goal.md）。
- **工具 goal 指令段**：按 `../templates/next-goal.md` 的七字段句式填——目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件。句式已内联，**不依赖外部 skill**；装了 `qiaomu-goal-meta-skill` 可用它打磨措辞后原样写入该段。**其余段落始终按模板补齐**。
- **职责边界**：goal 是 plan 某一行的展开——只能引用 `R<n>`，不得新增需求；只读切片状态，不得写入或推进；统一 DoD 原样复制、只可追加不可删减。冲突时以 plan.md 为准。发现「本片按 plan 写的范围做不出来」，在 goal 写 `BLOCKED` 并回阶段 3 修 plan，**不得**自行改范围。
- ⚠️ **写入路径必须显式写绝对路径到 worktree 的 `.devloop/<id>/next-goal.md`**。血泪教训：agent 曾写到主仓导致 runner 读到旧 goal 困惑退出。prompt 里把目标路径原文写出来并要求 agent 写完后自检。
- goal 编译 agent 只写 next-goal.md，不改业务代码、不提交、不点火。
- next-goal.md 顶部记录 `attempt_id`、`spec_sha256`、`plan_sha256`、`goal_sha256`、`base_sha`、编译时 `head_sha`；impl report 与 acceptance 必须回写同一组绑定字段以及各自产生时的 `head_sha`。

详见 [goal 编译契约](goal-template.md)。完成标准是**门禁 D 退出码为 0**，不是子代理自报完成：

```bash
<path-to-skill>/scripts/devloop gate goal --file <worktree>/.devloop/<id>/next-goal.md \
  --spec .devloop/<id>/spec.md --plan .devloop/<id>/plan.md
```

它校验八个必备小节、七字段齐全、九个 header 字段非空、`GOAL_SHA256` 自校验，以及 spec/plan 无漂移。不过门禁不得点火。

### 小周期 2：impl runner 实现

runner 的唯一任务输入是 `.devloop/<id>/next-goal.md`（工具 goal 指令 + 阶段提示词）；必须原样消费，不得依赖主会话上下文。

#### host=tmux

首次进入小周期 2 时，从 `../scripts/launch-runner-template.sh` 复制到 `.devloop/<id>/run/launch-runner.sh`，按模板注释改完五处配置（包括 `DEVLOOP_ID`、worktree 绝对路径、impl 名称、代理、impl 命令行）：

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

细节见 [Orca 执行规程](orca-host.md)。摘要：

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

1. 用户显式 `--reviewer=X`：用 X；若 `X == impl`，**警告**并用提问通道请用户明确授权；未授权不得启动同工具验收。
2. 用户未指定：按上表选与 impl 不同的工具。
3. 候选均不可用或只剩一个工具：告知用户并用提问通道询问是否授权同工具；**不得**静默同工具验收。
4. 将最终 `host` / `impl` / `reviewer` 写入 plan 确认记录与 progress。

### 小周期 3：跨工具对抗验收（reviewer）

impl 完成后，必须启动 **reviewer**（默认 ≠ impl）。主会话**不得**仅凭自身通读 diff 代替 reviewer 下「全部完成」。

#### 启动前

1. 解析 `impl` / `reviewer` / `host`。
2. 核对 impl 已退出/idle，冻结其 terminal；记录当前 HEAD。主会话写自包含验收 prompt 到 worktree 绝对路径：
   `.devloop/<id>/run/<impl>-<slice>-acceptance-prompt.md`
   （含切片原文、覆盖的 `R<n>` 验收标准、本片相关知识路径与约束并要求先读、路径、git 范围、门禁、验收报告输出路径、`attempt_id` / `goal_sha256` / `base_sha` / 待验 `head_sha`、对抗清单、结论三选一）。
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
