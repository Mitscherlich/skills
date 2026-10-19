# Acpus 真实端到端验证记录

验证日期：2026-10-20（Asia/Shanghai）。范围：安装 → 真实 ACP Agent → 并行开发 → 进度观测 → 暂停/恢复 → 集成测试 → 跨工具验收。不是用假 Agent 验证调度。

## 环境与任务

- Acpus 0.16.1，Node 24.15.0，Bun 1.4.3；Codex ACP 2.2.2，Claude ACP 0.84.0。
- 全局安装 Acpus；测试使用独立 `ACPUS_HOME` 和临时 Git 仓库，不修改真实项目业务代码、不推送。
- 两个 Codex Agent 分别生成 slug 和 median 模块；使用独立 worktree，确定性 Task 落盘、执行预置测试/严格类型检查并提交。Agent 为 `approve-reads`，本测试不验证 Agent 自主写工具权限。
- 单一集成 Task 顺序 cherry-pick，运行完整测试和类型检查，再由独立 Claude Code 工具验收，assert 强制检查其结构化 accepted 字段。工具名不保证底层模型厂商，沿用本机已配置的模型服务。
- 并发上限 2，Agent timeout 5m，Task timeout 1m，暂停检查点 timeout 3m；响应格式自动修复次数设为 0，以直接暴露协议问题。

## 已核验结果

主 Run：`20261020004928B80D19197C4C424672C4`，最终 `completed`，8 个叶节点全部通过。

| 检查 | 实测证据 |
|---|---|
| 并行调度 | 两个 Agent attempt 开始时间差 3ms，生命周期重叠 20.079s |
| 真实并行交互 | settled turn 时间分别为 11.081s / 16.966s，两次 Agent turn 重叠 11.081s |
| 进度观测 | CLI 在完成前显示两个 running 节点；inspect 订阅返回节点完成/失败变化；公共 Runtime API 可读取节点、attempt、时间与接受结果 |
| 事件证据 | 主 Run 留存 24 个 hook 事件文件；事件序号用于排序，hook 本身不作为验收权威 |
| 暂停活跃 Task | pause 后 Run=paused，检查点 attempt 被取消，检查点未产生完成标记，集成节点尚未启动 |
| 恢复 | 检查点 attempt #2 完成；四个已完成分支节点的 acceptedAttemptId 在恢复前后完全一致，证明未重跑 |
| 局部故障恢复 | 并行组和 reviewer 分别经历一次有原因的重试；重试 reviewer 未重新执行已完成集成 |
| 最终验证 | 2 项行为测试、11 个断言及严格 TypeScript 检查通过；reviewer accepted=true；集成 HEAD 为 `991de1ad99dcafe68db5cd5d95ad6b80ef203cc1` |

补充 Run：`20261020005744953FC7A6C36A54D2AB25`。移除临时 Agent 启动覆盖，使用修复后的内置 codex/claude 启动方式，并行执行真实结构化响应探针；两个响应值及两个 assert 全部通过，用时约 18s。

活跃 Agent 的暂停单独验证，结果与活跃 Task 不同：

- Run `2026102001011512574A9F10E621F50FD7` 在初始化阶段取消后 resume 成功，但暂停前没有模型活动证据，不能据此宣称中断模型交互成功。补做的 Timeline 文本监听也未捕获中途暂停机会。
- Run `202610200107440413349B03B7F7E124EE` 通过公共 target summary 确认 `provider_observed`、pulse=`responding`，已收到 `<ACP` 响应片段，然后执行 pause。Run=paused，活跃 attempt 被取消；直接 resume 则出现 `session_checkpoint_unknown` / `terminal_unknown`，保留这个失败结果。
- 核对这是无工具调用、无业务副作用的生成任务后，从失败 Run 的 `active_agent` fork 为 `20261020010844AC9006A1037FC8BBCB10`，新会话约 65s 完成；逐项校验返回的 200 个整数及平方全部正确。证实可通过新会话恢复，**没有证明同会话 resume 可用**。实际开发任务必须先检查已有写入和外部副作用。

## 发现并处理的问题

1. **CLI 健康不等于 Agent 就绪。** 首次并发启动触发 30s ACP capsule 初始化超时，后续直接启动发现 npx 安装缺少 Codex 平台二进制。先用已安装 Codex 验证主流程，再补齐该适配器缓存的可选依赖；内置启动方式的补充 Run 已通过。安装指南加入依赖预热、真实探针和 `CODEX_PATH` 排障，不再把适配器 `--help` 的退出码当就绪证明。
2. **Claude auto 模式污染终态响应。** 完整 `finalResponse` 中 `</ACPUS_OUTPUT>` 后追加了网关警告，导致 output_framing 失败。仅将测试项目的 Claude 权限模式设为 default 后，局部重试成功；没有删警告、伪造验收或放宽输出校验。后续项目按安装指南核对自身配置。
3. **观测命令及暂停语义不够准确。** 0.16.1 的 timeline 必须传 target；root Timeline 在 Run paused 时仍可显示 running。规程已补充正确命令和 Run/attempt/下游联合核对方法，明确 resume 是重开未完成 attempt。
4. **重试编号不是累计预算。** 整个 parallel 组重试后子节点 attemptNo 可重新从 1 开始。规程已禁止据此计算累计次数，并说明该版本没有统一的跨 retry/fork 总预算开关，不能只写计划字段就声称硬限制已生效。
5. **devloop 检查遗漏运行控制和 Runtime 健康。** detect-mode 增加 pause/resume/fork 能力探测及原生 doctor；原生检查失败返回 unhealthy，始终明确 `acpus_agents_status=unchecked`。补充回归用例。
6. **暂停活跃模型后未必能直接恢复旧会话。** 0.16.1 对无法确认终态的会话拒绝自动连续执行。已在执行规程和安装排障中加入检查副作用后定点 fork 的恢复分支及累计预算要求；这是已实测的规避路径，不是修改上游引擎或放宽会话安全检查。观测规程同时加入 pulse/会话检查点，避免只监听完整文本活动而错过干预窗口。

## 原始证据与复查

本次本机证据根目录：`/private/tmp/devloop-acpus-e2e.j8C32y`。其中 `workflow.ts`、`input.json` 为主流程源码/输入；`before-pause.json`、`paused.json`、`final.json` 为公共 Runtime API 的只读快照，`verification-summary.json` 为程序断言结果；`events/` 为事件文件，`project/`、`slug-worktree/`、`median-worktree/` 为代码与提交。

活跃 Agent 证据：`agent-active-checkpoint.json`、`agent-active-paused.json`、`agent-active-resume-failed.json`、`agent-recovered.json` 分别保留暂停前真实响应、取消结果、同会话恢复失败、新会话完成结果；`pause-on-checkpoint.ts` 为有界检测与暂停脚本，`agent-pause-verification-summary.json` 汇总程序断言。

修复后 devloop 回归：19 个测试文件、430 项断言通过；`git diff --check` 及本地文档链接检查通过。最终原生 doctor 显示 5 个 Run、0 个 runnable、无 idle-stop 阻塞；其中活跃 Agent 的同会话恢复失败 Run 按原样保留，未改为成功。

临时目录可能被系统清理；本记录保留关键结论，不承诺这些路径永久存在。原始 turn/事件可能含本机模型服务配置，不应直接公开整个运行目录。

目录仍存在时，在 `project/` 内运行：

```bash
ACPUS_HOME=/private/tmp/devloop-acpus-e2e.j8C32y/runtime acpus runs inspect 20261020004928B80D19197C4C424672C4
ACPUS_HOME=/private/tmp/devloop-acpus-e2e.j8C32y/runtime acpus runs artifacts 20261020004928B80D19197C4C424672C4
bun test
bun run typecheck
```

这是小型真实集成测试，不是大型项目吞吐基准；不能据此把 1–2 天的任务外推为固定小时数。未验证机器重启、网络故障和跨版本迁移；Run 总预算仍需要额外有界控制。原协议的需求签署和哈希门禁另由 devloop 自动化测试覆盖，本记录不伪造生产任务的签署。
