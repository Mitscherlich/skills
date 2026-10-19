# Acpus 执行模式

仅在 `execution_mode: acpus` 时读取本规程。默认模式继续使用 [loop.md](loop.md)。这是 skill 协调者驱动的 Acpus 适配：devloop CLI 管理材料、门禁和路由；协调者按本机 Acpus 指南编译、提交并跟进 workflow，CLI 的 `next` 本身不启动任务。

## 1. 选择模式与点火前检查

```bash
<skill>/scripts/devloop init --id <id> --title <标题> --mode acpus
<skill>/scripts/devloop doctor --mode acpus
<skill>/scripts/devloop next --dir .devloop/<id>
acpus skill read
```

`init` 将模式写入 intent，后续 `init --stage plan` 自动继承并追加 `plan-acpus.md` 合同。未安装 Acpus 也可以准备草稿，但执行前 doctor 和下述实际能力检查必须通过。新任务不指定模式即 default；恢复沿用记录，不根据机器环境切换。

已有任务切换模式：先暂停旧后端，确认活动写入已停并保留现场；展示变更，按已有授权范围修订 intent/plan 的模式、执行合同及下游 hash，并按管线规程重审受影响内容。历史验收不重写。只传不同的 `--mode` 会报冲突，`--force` 也不能绕过模式一致性。

正式 A/B/C、真实执行授权、前置条件、执行区交接仍全部成立。按 [安装指南](installation-acpus.md) 检查版本和 ACP agents，记录实际 CLI 路径/版本、实现与验收 profile、`ACPUS_HOME` 的实际绝对路径及 Runtime workspace cwd。doctor 不验证 Agent；首次启动前用真实结构化输出探针验证选定的 impl/reviewer。此模式由 Acpus 管理执行和运行状态，不启动 tmux/Orca runner、default 哨兵或第二套重试循环。

## 2. 先冻结契约，再拆并行子图

F 是顺序验收批次，plan 仍至多一个 `open`；**同一个 F 内的 T 子任务可以并行，不同时推进多个 F**。设计时先稳定接口/共享数据契约，再将可独立实现的模块放入同一批次；真实依赖用 T 的依赖列连接，不能为了并行遗漏依赖。

plan 的 Acpus 合同必须包含：

- T ID、所属 F、前置 T（逗号分隔或 `-`）、允许写入路径、可执行验收命令。T ID 全 plan 唯一，依赖只能在同一 F 内；跨批次依赖由 F 的顺序承接。
- `acpus_max_parallel`：同时运行的 agent 上限，包含 reviewer；`acpus_max_attempts`：每个逻辑子任务及集成阶段累计尝试上限，包含首次尝试。
- `acpus_task_timeout_minutes`、`acpus_run_timeout_minutes`：单次子任务及整个批次的执行时限；还要写清同一失败重复出现的停止条件、运行检查点和必要的费用/额度上限。

门禁检查正整数预算、子任务覆盖、引用、重复 ID 和依赖环。协调者仍须查证路径重叠、共享生成文件/锁文件、数据库、端口、外部副作用与接口语义；有冲突就串行化或加依赖，不能靠“模块名不同”认定独立。

每个 T 独立 branch/worktree、测试资源和产物目录。下游 T 从已验收的依赖提交构建基线，不从并发写入中的目录读取代码。共享 schema、入口配置、lockfile 优先由单一任务负责，统一集成由单一 integrator 串行写入执行分支。reviewer 只读代码，单独目录写 acceptance。

## 3. 编译与提交 workflow

1. 对当前 F 生成新 attempt、完整批次 goal，通过门禁 D。创建 `run/acpus/<F>/<attempt>/`，保存冻结的 intent/spec/plan/goal、它们的 hash、base SHA、workflow 源码与版本信息；运行中不覆盖。各 T 使用其下独立目录保存 prompt、日志、报告和尝试证据，不在并行期间调用会搬移其它任务产物的整目录 archive。
2. 按**本机 `acpus skill read`** 的 TypeScript API 编译 `workflow.ts`，启用严格类型检查；新建 Node 项目时按项目要求用 Bun。不要套用旧 YAML 示例，也不要仅凭本文猜 SDK 导入和字段。将运行依赖固定在已验证版本。
3. 每个任务上下文自包含：R/I/F/T 来源、冻结输入、允许写入边界、依赖提交、基线、验证命令、相关知识、权限、预算、输出 schema 和报告路径。T 可运行针对性测试，但不能把完整 F 的统一 DoD 删掉；最终集成节点必须执行完整 DoD。
4. 图包含：前置条件/绑定校验 → 依赖驱动的实现与局部验证 → 独立验收 → 串行集成 → 全批次测试与跨工具 reviewer → 最终证据检查。局部失败只修复受影响的任务及失效下游；人工裁决与真实凭据缺失通过 Runtime 的等待/暂停机制暴露，不在 agent 内无限聊天等待。
5. 将并发、尝试次数和 deadline 落到该版本 Runtime/Workflow 支持的配置及有界控制流，不能只写在 prompt 中。0.16.1 的 parallel/fanout 用 `maxConcurrency`，Task/Agent 用 `timeout`；启动 daemon 前可用 `ACPUS_RUNTIME_RUN_MAX_LEAF_CONCURRENCY` 限制整个 Run 的活跃叶节点（含 Task，不只 Agent）。`ACPUS_AGENT_RESPONSE_REPAIR_MAX` 是**单 attempt 内**响应修复 turn 上限，不是业务重试预算。该版本没有可直接填写的统一 Run 总时限或跨 retry/fork 累计尝试配置，须由外部有界控制及持久记录落实；未落实时如实标记该约束未满足，不宣称可无人值守。累计记录包含显式 retry/fork；本次实测重试 parallel 组后，子节点 attemptNo 可重新从 1 开始，不能只用当前 attemptNo 判断剩余预算。
6. 完成节点须校验测试退出码、结构化报告及验收结论、hash 和 reviewed HEAD；检查失败必须使流程失败或等待处理，不能以返回 `accepted: false` 后正常结束来表示拒绝。workflow 成功仍不代替协调者的最终验收核对。

从记录的同一个 Runtime 工作目录、相同 `ACPUS_HOME` 使用同一可执行文件运行。以下为当前命令族，具体参数以本机指南为准：

```bash
acpus workflow check <workflow.ts>
acpus workflow viz <workflow.ts> --out <workflow.html>
acpus workflow run <workflow.ts>
acpus runs inspect <run-id> --await-decision
```

`check` 不通过不得提交；`viz` 是静态图，用于审阅依赖，不能当实时监控。`run` 默认提交后返回，协调者立即记录返回的 Run ID 与 F/attempt 映射、workflow hash、预算起点和 Runtime 工作目录，再跟进状态。如果命令超时/退出而无法确定是否提交，先核对 Runtime 中原 Run，禁止盲目重新提交。参见 [官方 CLI 说明](https://github.com/kelvinschen/acpus/blob/main/specs/cli-spec.md)。

## 4. 中途可见、可干预

每次恢复先 `next --dir` 确认材料与当前 F，再从 progress 找到已有 Run ID 并 `runs inspect`，不能按 default 报告数量或终端哨兵猜阶段。Runtime 是 T 的运行状态权威，plan 是 F 的验收事实源；progress 只保存定位信息、决定和证据摘要。

```bash
acpus runs inspect <run-id>
acpus runs inspect <run-id> --target root --timeline --await-decision
acpus runs inspect <run-id> --target <node-or-attempt> --forensics
acpus runs inspect <run-id> --follow
acpus runs pause <run-id>
acpus runs resume <run-id>
acpus runs retry <run-id> --target <node-or-@ref>
acpus runs steer <run-id> --target <active-agent-or-@ref> --instruction '<已授权的修正>'
acpus runs fork <run-id> --workflow <revised-workflow.ts>
acpus runs fork <run-id> --target <source-occurrence>
```

使用事件/等待接口跟进，避免每几秒唤醒模型轮询。遵守当前平台等待时长及进度汇报约束，必要时用可让出的调用保持响应。CLI 文本供协调者和用户阅读；自动判定应使用包 API/MCP，不用 grep 解析自然语言。退出 follow 只是断开观察，不等于停止任务。

0.16.1 的 `--timeline` 必须同时传 `--target`，整个图可选 `root`。暂停后 root 逻辑 frame 的 Timeline 可能仍显示 running；暂停是否成立核对 **Run 的 paused 状态、活跃 attempt 已取消/清理以及下游未启动**，不能仅看该标签。恢复会为未完成任务创建新 attempt，不是从原进程指令位置继续；任务的写入与提交必须可重入，已完成结果可复用。

**活跃 Agent 的恢复存在会话边界。** 本次在 `provider_observed` 且已收到响应片段时暂停，resume 后以 `session_checkpoint_unknown` / `terminal_unknown` 失败；不能承诺所有 Agent 都可直接 resume。遇到此错误停止同会话自动重试，先检查旧 worker 已停止、分支 diff/提交和外部副作用，确认重放在既有授权与预算内，再用 `runs fork <run-id> --target <source-occurrence>` 创建新会话。target 不带 `#attemptNo`；它会重算目标及后续受影响工作，必须核对继承的已完成证据和依赖，不能当作只重跑一行。progress 记录源/新 Run、取消/失败 attempt、恢复原因、已有提交和剩余预算；恢复后重新验收，旧 Run 保留失败事实。若副作用无法判明则先停在该节点，不能盲目重放。

模型正在工作不一定立即产生 Timeline 的完整 activity 条目；只监听最终文本可能错过干预窗口。使用 Runtime 公共 API 的 target summary/pulse 和 `agentSession.checkpoint` 辅助区分初始化、请求已发出、provider 已响应与终态；本次 `provider_observed` + responding pulse 确认了活跃交互。订阅的 update 可能只有 activity 变化标记，不能要求每次必有 timeline 文本。必要的有界状态采样放在脚本内，不反复唤醒模型。

需要实时图时使用 `acpus web`，`workflow viz` 仍是静态图。需要留存阶段证据时，0.16.1 可在项目 `.acpus/config.json` 配置 `node.started/completed/failed` 和 `run.*` hooks，逐事件写独立文件；按 `eventSequence` 排序，不假设异步 hook 落盘顺序。Hooks 在 daemon 启动时加载，改配置需等其安全退出后再启动。Hook 失败不会影响 Run，因此它适合观测，不能充当预算硬门禁。事件可能含冻结输入和 Agent 配置，应留在本地过程目录并控制内容，勿直接公开完整事件。

开工、接口契约完成、分支验收完成、集成验收、故障/暂停时更新 progress，并向用户提供有意义的变化：

- 当前 F/Run、各 T 的运行/等待/完成状态、等待原因、已用时间与预算余量。
- 已验证的测试、提交/diff 或可运行演示；需求覆盖和计划偏差，避免用节点数量冒充业务完成度。
- 失败节点、归一化失败原因、累计修复次数、下一步动作。连续相同失败或预算耗尽时停止该分支及依赖它的下游，保留其它分支证据，报告可执行的处理选择。

额度/费用/时间等指标缺失时写“未知”，不能记为 0 或编造 ETA。用户可以先暂停再调整；恢复前检查活动 worker 已停止、工作树状态与副作用。Runtime 持久化不等于 Git/外部操作自动回滚或 exactly-once；重试要检查上次提交和产物，避免重复应用。官方能力边界见 [Runtime 契约](https://github.com/kelvinschen/acpus/blob/main/specs/runtime-spec.md)。

`steer` 仅调整已授权范围内的实现策略；范围、依赖、写入边界、预算等实质变更先走计划增量审阅，再编译新 workflow/fork。fork 不清零预算，也不能用新 Run 掩盖重复失败。

## 5. 集成验收与收尾

所有依赖结果通过局部验收后，由 integrator 按拓扑顺序串行合入；冲突只由 integrator 处理。独立 reviewer 核对整个 F 的 R 覆盖、完整 DoD、集成测试及计划偏差，输出原协议要求的 attempt/spec/plan/goal/base/head 绑定和 `全部完成` 结论。并行分支通过不等于最终集成通过。

协调者取得 advance 锁后重新核对冻结输入与当前材料、Run 最终证据、当前 HEAD=reviewed HEAD；全部成立才将 F 记为 done，记录验收目录和 Run ID，开启下一个 F。只有协调者更新 plan，agent 不得写 plan 或共享 next-goal。验收路径使用 `run/acpus/<F>/<attempt>/...`，替代默认报告文件名；字段与完成标准保持一致。

advance 后 plan hash 变化是下一批次的新基线，不能反写已冻结的历史报告。所有 F 完成后读 [closeout.md](closeout.md) 核对原承诺、归位知识并交接发布。未经授权不 push/deploy；不因 Runtime completed、预算耗尽或切换下一轮而宣布交付成功。
