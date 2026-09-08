---
name: devloop
description: 当用户要用 devloop 启动交付、继续已有 .devloop/<id>、初始化或维护项目知识库、收尾归档、从上一轮选择新 intent 时使用。支持 intent 确认、spec/plan 联审、独立实现与验收，以及发布交接。
version: 0.9.1
---

# devloop：从意图到可验证交付，再把知识带入下一轮

默认两次人工确认：**简短 intent → spec/plan 联审并授权执行**。实现由独立 runner 完成，跨工具 reviewer 验收；需求定稿后维护 `docs/knowledge/specs/`，收尾将规格、领域知识、经验与 ADR 分别归位，再提出有证据的下一轮候选。默认只做本地 commit。

## 先识别入口

**所有入口必做**：找到实际项目/执行 worktree，按 [知识维护协议](references/knowledge.md) 运行 `setup --check`；缺入口则执行 `setup`，然后按索引读取本轮相关知识。用户限定只读时只报告缺口。每次会话进入或切换 worktree 检查一次，巡检不重复扫描；目录存在不代表内容已查证。

| 用户意图 | 动作与完成条件 |
|---|---|
| 初始化 / 维护知识库 | 按知识维护协议建立入口、查证本次相关资料、更新知识及索引；不创建交付任务 |
| 新开 devloop | 读项目规范和已有知识 → 初始化 → 澄清 intent → 设计联审；进入执行前须有真实授权 |
| 继续已有流程 | 找到实际执行 worktree，运行 `next --dir`；保留原确认、切片和验收边界 |
| 收尾 / 归档 | 直接读 [收尾协议](references/closeout.md)，检查当前切片和证据；无需重新 grill |
| 需求 settle / 规格归档 | 按知识维护协议把已确认需求合并到 `docs/knowledge/specs/<capability>/spec.md`，同步领域/决策引用；保留本轮签署原件 |
| 从上一轮继续迭代 | 读取上一轮 closeout 的候选和相关项目知识；仅将已选候选变成新 ID 的 intent，补问新增不确定性 |

用户可直接说：

- `用 devloop 做 <需求>，先给 intent 草稿，只问阻塞问题，spec/plan 联审。`
- `收尾 .devloop/<id>：核对验收，提炼项目知识，将 spec/领域/经验/ADR 归位，并给下一轮候选。`
- `从上一轮 closeout 的候选 N1 新开 devloop；沿用仍有效的决定。`

## CLI 入口

```bash
<skill>/scripts/devloop setup --check
<skill>/scripts/devloop setup
<skill>/scripts/devloop init --id <id> --title <标题>
<skill>/scripts/devloop next --dir .devloop/<id>
<skill>/scripts/devloop gate intent --draft --file .devloop/<id>/intent.md
<skill>/scripts/devloop review-packet --devloop-dir .devloop/<id>
<skill>/scripts/devloop init --id <id> --stage closeout
<skill>/scripts/devloop run-tests
```

`next` 只读，返回 `stage/action` 和失败项。`await_*_review` 表示等待已有材料的审阅，不要继续制造问题。CLI 详细契约见 [control-plane](references/control-plane.md)。CLI 沿用 POSIX shell 和标准工具；规格语义合并按知识维护协议执行。

## 1. Intent：先写草稿，只问当前阻塞

1. 结合入口已读取的项目知识和需求材料查代码确认事实；已有裁决检查是否仍适用，直接引用。
2. `init` 先落盘。新 intent 默认 `review_mode: joint`，初始化维护 `.devloop/.gitignore`，只忽略任务下的过程文档和 run/；持久 specs 与该忽略文件可提交。已有跟踪不会被自动取消；暂存始终使用明确路径。
3. 写一屏可读的核心：问题与受影响者、期望结果、本轮范围、硬约束与非目标。先确认范围，再深入范围内的取舍。架构红线可进 intent；实现文件、CSS/依赖配置等放 spec/plan。
4. 维护 design tree / frontier，但只询问会阻止理解业务目标、划定范围或遵守硬边界的问题。一次一题，题干包含「已定什么、这次决定什么、影响什么、推荐与取舍」。用平台适用的提问通道；授权依平台规则取得，不能把沉默当确认。
5. 每题后更新**当前生效**的正文和 I 编号。替代旧决定时保留稳定 ID，记录替代原因和用户来源到 progress，同步所有受影响段落。每 3 个实质裁决或会话恢复时，用不超过 5 行回顾已定范围、变化及剩余阻塞项。
6. 事实由 Agent 查证，可逆技术选择由 Agent 提出方案；后续阶段问题按 [管线契约](references/pipeline.md) 的 `stage/owner/due` 格式转交。无需把所有未知都在 intent 清零。
7. 当业务目标和硬边界已明确、本阶段无阻塞、后续问题有归属和期限时，运行 intent 草稿检查；给用户审阅当前 intent。取得实际确认后记录来源、审阅人与结论，运行正式门禁 A。

提问超过约 5 个关键决策仍无法收敛时，先总结导致发散的依赖，收窄这一轮可交付范围或安排查证；这是诊断提醒，不是省略必要裁决的硬限额。用户已要求完整范围时，保留范围并说明剩余阻塞。

若用户已有成熟规格，允许从 spec 开始，但先将既有目标、红线和授权来源整理成简短 intent，经用户确认或引用已有明确确认；不要重新访谈已定问题。

## 2. Spec + Plan：草稿联审，正式门禁仍分开检查

按 [pipeline.md](references/pipeline.md) 编译与签署，模板在 `templates/`。

1. spec 应用项目规范，形成 R 需求表、设计和关注点。逐项接住 intent 转交的问题：设计事项解决在 spec，执行条件进入 plan 并标明阻塞切片，发布条件进入发布交接。不要丢失原 ID。
2. 新流程 `joint`：spec 的 `gate spec --draft --intent ...` 通过即可编译 plan 草稿。plan 包含 R→F 追溯、独立可验证的切片、统一 DoD 和执行边界。
3. 两份草稿检查通过，向用户展示同一份联审摘要：目标与范围、关键设计取舍、风险、切片与验证、仍需人裁决的增量、执行及收尾授权。全文提供链接；优先处理关注点，不让用户重读没有变化的内容。
4. 用户联审通过后，以同一真实确认来源填写 spec 签署与 plan 确认记录，按 pipeline 的顺序封存绑定。任何语义变更都展示增量并重审受影响部分；签署封存后按知识维护协议将定稿需求合并到 `docs/knowledge/specs/`，标明实现状态。正式 intent/spec/plan 全通过后才进入执行。
5. 多人职责分离、用户要求逐阶段审阅时，将 intent 的 `review_mode` 设为 `separate`。无此字段的旧流程仍按分别签署执行；继续旧流程时不自动改模式或重置已有授权。

gate 校验结构和文件绑定，不能证明签名是谁写的，也不能判定语义一致。协调者须核对实际用户消息或外部批准记录；模型不代签。

## 3. 执行：按当前 attempt 核验

进入 loop、恢复 runner、处理停滞或重开切片时，读取 [执行协议](references/loop.md)；只有确定 host=orca 时再读取 [Orca 规程](references/orca-host.md)。

必须保留的边界：

- 协调者编排，业务实现交给 host 上的 impl runner；默认与 impl 不同工具的 reviewer 独立验收。同工具验收须已有明确用户授权。
- 每次点火生成新 attempt；goal 通过门禁 D，并绑定 spec/plan/goal/base/head。报告和 acceptance 先写临时文件再 atomic rename。
- reviewer 只写验收报告，不改代码、不提交、不推进 plan。当前 HEAD 与 reviewed head 一致才能推进下一片。
- goal 是 plan 某行的展开，不能新增需求。原承诺未满足留在本轮，不能改成下一轮候选来宣布完成。
- 终端存活、日志变大、出现最后一次重试字符串都不是完成或失败证明；以退出状态、完整产物和绑定检查判断。

交接到执行 worktree 时，显式复制未跟踪的 `.devloop/<id>` 并核对 plan hash；源目录留下执行区指针，之后只维护执行区。不得假设未提交文件会跟随 worktree 创建。依赖未提交业务改动时按用户已授权的 commit/patch/当前 checkout 方案交接。

## 4. 收尾：规格与知识归位、发布交接、下一轮

当 `next` 返回 `finalize` 或用户要求收尾时，按 [closeout.md](references/closeout.md) 执行：

1. 核对每条需求、切片验收与未验证项；有原承诺缺口则修复或报告阻塞。
2. 用 `init --stage closeout` 建收尾清单，按知识维护协议将 spec 归入 `docs/knowledge/specs/`、共享领域知识归入 domain、经验归入 playbooks、ADR 归入 decisions，并同步索引；长日志留本地任务目录。知识文档的改动也走审阅与授权范围，不能改变原验收报告。
3. 明确区分本地已验收、已发布、效果已验证。发布复用项目现有流程；没有发布授权时交付完整发布材料，不推送或部署。
4. 候选可以为零；每项有证据、价值、最小验证和处置。默认仅提出候选；已选或符合既有预授权范围的才新开 ID。
5. 停止本轮写入，核对规格与知识的持久去向、必要证据及提交状态后汇报。过程材料按 `.devloop/.gitignore` 留在本地；清理须有明确授权且持久产物已安全保存。

## 旧流程与后续优化

0.6.x 的 intent/spec/plan 和验收原件仍可读取；对旧流程收尾不需要升级模板或重签历史文档。新严格检查暴露缺口时如实处理；历史自然语言确认可依据原授权规范化字段，并保存原文来源。详细迁移见收尾协议。

本轮没有引入常驻监控服务或新的发布平台。通过真实新流程观察「关键问题数、重复确认数、开工后需求返工、错误完成次数」，继续调整。演进记录见 [ROADMAP.md](ROADMAP.md)。
