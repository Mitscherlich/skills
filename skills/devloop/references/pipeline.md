# devloop 交付管线：intent → spec → plan → loop

> 结构参考 Anthropic《The AI-native SDLC playbook》的 Plan / Design / Build / Test / Deploy 分层：
> 每一阶段产出**一份命名产物**，每一次阶段跃迁都有**一道准出门禁（人 + lint）**。
> devloop 的差异化在于：门禁不是 prose 提醒，而是 `devloop gate <stage>` 的退出码；
> 且 Test / Deploy 两层被压缩成 loop 内的「impl 门禁 + 跨工具对抗验收」。

## 总览

| # | 阶段 | 产物 | 谁写 | 准出门禁 | 通过后 |
|---|---|---|---|---|---|
| 1 | grill / 意图识别 | `intent.md` | grill 主会话（活文档，边聊边回写） | `devloop gate intent` + **人工审阅签字** | 编译 spec |
| 2 | 设计 | `spec.md` | 编译子代理（消除过程性记录） | `devloop gate spec --intent` + **签署** | 编译 plan |
| 3 | 规划 | `plan.md` | 编译子代理（切片 roadmap） | `devloop gate plan --spec` + **确认记录** | 进入 loop |
| 4 | 实现 loop | `next-goal.md` + `run/*` | goal 编译子代理 + impl runner | `devloop gate goal` + 跨工具 reviewer acceptance | 推进下一片 / 收尾 |

阶段跃迁的合法性由状态机保证：

```bash
devloop stage can --from intent --to spec    # 0 允许
devloop stage can --from intent --to plan    # 1 拒绝——不能跳过 spec
devloop stage transitions --from plan        # loop / spec（打回）
```

任何时候问「现在该干什么」，用一条命令，不要重读全文：

```bash
devloop next --dir .devloop/<id>
```

它会依次跑三道门禁，返回 `stage=` 与 `action=`（`init_intent` / `grill_intent` / `compile_spec` / `fix_spec` / `compile_plan` / `fix_plan` / `work_open_slice` / `finalize` …），门禁不过时把每条 `fail=` 原样带出来。

## 防漂移：上游 sha 绑定

`spec.md` 头部写 `intent_sha256:`，`plan.md` 头部写 `spec_sha256:`，值取自上游门禁通过时输出的 `sha256=`。
门禁会重算上游文件的 SHA-256 并比对：**上游被改过而下游没重编译，门禁直接失败**。

这条约束的意义：grill 结束后又追加了一条裁决，spec 却还是旧的——这种沉默漂移在纯 prose 流程里根本发现不了。

`next-goal.md` 头部的 `SPEC_SHA256` / `PLAN_SHA256` 把链条延到第四级：spec 或 plan 在 loop 中被改过而 goal 没重编译，`gate goal` 直接拦下。

```bash
ISHA=$(devloop gate intent --file .devloop/<id>/intent.md | sed -n 's/^sha256=//p')
# 把 $ISHA 写进 spec.md 的 intent_sha256 行
```

## 阶段 1：grill → intent.md

`devloop init --id <id> --title <标题>` 先落盘 `intent.md` 骨架与 `progress.md`，**然后**才开始 grill。

活文档纪律（这是本阶段唯一容易翻车的地方）：

1. **每个裁决点一解决就回写**，追加到 `## 裁决记录` 的编号列表，不要攒到最后补记。编号在下游被引用为 `I-<n>`。
2. 问题陈述 / 期望结果 / 影响范围 / 约束在 grill 过程中被修正时，**原地改写**，不要在文末堆「修订说明」——过程留痕交给 git 和 `progress.md`。
3. 还没想清楚的问题写进 `## 未决问题` 的 `- [ ]` 列表。**未勾选的条目会挡住门禁**，这是 grill 是否收敛的机器判据。
4. 收敛后 `## 未决问题` 写成一行 `- 无`。

访谈算法（design tree / frontier / 提问通道逐题问）内联在 `SKILL.md` 阶段 1，无外部 skill 依赖。
覆盖面：所有会影响**架构边界、写入范围、验收标准、凭据/人工输入、执行深度**的问题都要有裁决。

收敛判据只有一个：访谈侧的「frontier 为空即结束」与门禁侧的 `I-openq`（未决问题无未勾选项）**是同一件事的两种说法**——门禁就是访谈是否真收敛的机器判据。

### 门禁 A：`devloop gate intent`

| 检查 | 判据 |
|---|---|
| `I-heading` | 七个必备小节齐全 |
| `I-placeholder` | 无 `{{...}}` 未填占位符 |
| `I-todo` | 无 TODO / TBD / FIXME / XXX / 待填 / 待补 / 待定 |
| `I-decision` | `## 裁决记录` 至少一条编号裁决 |
| `I-openq` | `## 未决问题` 无未勾选 `- [ ]` |
| `I-signer` / `I-verdict` | `## 人工审阅` 有审阅人且结论为「通过」 |

`I-signer` / `I-verdict` 是**人的门禁**：模型不得代签。审阅人要真的读过 intent 全文——这正是 playbook 里「product owner reviews and approves」的落点。审阅结论为「打回」时回到 grill，不得往下走。

## 阶段 2：intent.md → spec.md

编译子代理的任务是**把过程变成规格**。派活时 prompt 必须包含下面这段（改编自 playbook 的 Stage 2 设计提示词，保留其「加载组织规范 + 显式暴露策略冲突」两个要点）：

> 读取 `<绝对路径>/.devloop/<id>/intent.md`，产出一份把它接入现有代码库的**需求与设计规格**。
> 应用你可用的项目规范（CLAUDE.md / AGENTS.md / 编码规范 / 安全策略 / UX 标准 / 既有 ADR），使规格符合这些约束。
> 完整写入 `<绝对路径>/.devloop/<id>/spec.md`，达到可直接交付给实现方的程度。
> **明确写出任何关注点，尤其是你无法同时满足相互冲突的策略的地方**——写进「关注点与冲突」表，给出建议取舍和需要谁拍板，不要私自选一个然后掩盖。
> 结构按 `<skill>/templates/spec.md`。头部 `intent_sha256:` 填 `<门禁输出的 sha256>`。
> **消除过程性记录**：不得出现裁决历史、未决问题、问答轮次、grill 对话痕迹；intent 的裁决只以 `I-<n>` 形式出现在需求表的「来源」列。
> 只写 spec.md，不改任何业务代码，不提交。

产物纪律：

- 每条需求一个稳定 ID `R<n>`，四列（需求 / 验收标准 / 来源）都不能空。**验收标准必须可执行**——可跑的命令、可 grep 的断言、可观测的指标，不能是「体验更好」。
- `## 关注点与冲突` 宁可写「无」，也不要漏掉真实冲突。这是本阶段对下游最有价值的输出。

### 门禁 B：`devloop gate spec --intent <intent.md>`

| 检查 | 判据 |
|---|---|
| `S-heading` / `S-placeholder` / `S-todo` | 同 A 的结构与占位符检查 |
| `S-req` / `S-req-cell` | 至少一行 `\| R<n> \|`，且每行描述/验收标准/来源三列非空 |
| `S-procedural` | 不得残留 `## 裁决记录` / `## 未决问题` / `## 对话记录` / `## 过程记录` / `## 人工审阅` |
| `S-procedural-line` | 不得残留 `Q:` `A:` `问：` `答：` / `第 N 轮` / `grill 记录` |
| `S-signer` / `S-verdict` | `## 签署记录` 有签署人且结论为「通过」 |
| `S-bind` | `intent_sha256` 与当前 intent.md 一致（无漂移） |

`S-procedural*` 就是用户要求的「消除过程性的记录」的机器判据：spec 里出现问答体或裁决历史，一律不放行。

## 阶段 3：spec.md → plan.md

编译子代理 prompt 要点：

> 读取 `<绝对路径>/.devloop/<id>/spec.md`，产出**整体方案执行计划** `<绝对路径>/.devloop/<id>/plan.md`，结构按 `<skill>/templates/plan.md`。
> 把 spec 的每条 `R<n>` 拆进切片 roadmap，并在「需求追溯」表里给出 `R<n> → F<n>` 映射——**每条 R 都必须被至少一个切片覆盖**。
> 切片粒度：一片 ≈ 一次无人值守 session 能完成的量（经验值 15–60 分钟 runner 时长、一二十个文件改动）。
> 切片间依赖**单向**（后片只依赖前片的 commit），禁止环。
> 涉及外部凭据 / 人工输入的片放最后并标 `paused(原因)`，到达时通知用户而不是硬跑。
> 状态词只允许 `open` / `done` / `pending` / `paused(原因)`，且**恰好一个 `open`**。
> 头部 `spec_sha256:` 填 `<门禁输出的 sha256>`。只写 plan.md，不改业务代码，不提交。

切片粒度自检（编译完自查一遍）：

- 一片 runner 时长 15–60 分钟？超过就拆，不足 10 分钟就合。
- 后片只依赖前片 commit？有环就重排。
- 每片有独立可验证的 DoD？验不了说明范围没想清，回 spec。

### 门禁 C：`devloop gate plan --spec <spec.md>`

| 检查 | 判据 |
|---|---|
| `P-heading` / `P-placeholder` / `P-todo` | 结构与占位符 |
| `P-roadmap` / `P-open` / `P-status` | 有切片行；恰好一个 `open`（或全 done）；状态词合法 |
| `P-trace` | 需求追溯表至少一行 `R<n> → F<n>` |
| `P-confirm` | 确认记录含确认人 / 确认时间 / 进入 loop 结论 |
| `P-bind` | `spec_sha256` 与当前 spec.md 一致 |

确认记录还要记：host / scheduler / 协调者 / impl / reviewer / 权限授权 / source_worktree / base_sha / plan_sha256 / control-plane 策略。这些字段门禁不逐一强校验，但缺失会在 loop 里立刻扎手——按 `templates/plan.md` 填满。

## 阶段 4：loop —— next-goal.md 与 plan.md 的职责边界

用户最容易踩的坑是让 `next-goal.md` 和 `plan.md` 打架。规则如下，**冲突时一律以 plan.md 为准**：

| 事项 | plan.md | next-goal.md |
|---|---|---|
| 需求集合 | 唯一来源（追溯自 spec 的 R） | 只能**引用** R 编号，不得新增需求 |
| 切片划分与状态 | 唯一事实源 | 只读；**禁止**写入或推进状态 |
| 统一 DoD | 定义 | 原样复制，可**追加**本片特有验收点，不得删减 |
| 本片实现细节 | 不写 | 唯一来源（代码锚点、分阶段任务、约束、BLOCKED 条件） |
| 生命周期 | 整个 loop 一份 | 每片每次 attempt 重新编译，旧的归档 |

`next-goal.md` 是 **plan.md 某一行的展开**，不是第二份计划。它由 goal 编译子代理产出：

- 「工具 goal 指令」段按 `templates/next-goal.md` 的七字段句式填：目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件。句式已内联，**不依赖任何外部 skill**；装了 `qiaomu-goal-meta-skill` 可用它把措辞打磨得更锐利，产出原样写入该段即可。
- goal 顶部必须写齐 `ATTEMPT_ID` / `SPEC_SHA256` / `PLAN_SHA256` / `GOAL_SHA256` / `BASE_SHA` / `HEAD_SHA`，impl report 与 reviewer acceptance 回写同一组绑定字段。

### 门禁 D：`devloop gate goal --file <next-goal.md> [--spec ...] [--plan ...]`

| 检查 | 判据 |
|---|---|
| `G-heading` / `G-placeholder` / `G-todo` | 八个必备小节齐全；无 `{{...}}`；无未完成标记 |
| `G-header` / `G-status` | 九个 header 字段非空；`STATUS` 取值合法 |
| `G-field` | 「工具 goal 指令」段七字段齐全且非空 |
| `G-goalsha` | `GOAL_SHA256` 等于「删除该行后」对全文算的 SHA-256 |
| `G-bind` | 传入 `--spec` / `--plan` 时校验对应 sha 无漂移 |

`G-goalsha` 的用处是让 report 与 acceptance 能凭一个值确认「验的就是派出去的那份 goal」：goal 被中途改过，三方 hash 就对不上。

若 goal 编译子代理发现「本片按 plan 写的范围做不出来」，**不得**自行改范围——在 goal 里写 `BLOCKED` 并回到阶段 3 修 plan（`devloop stage can --from loop --to plan` 是合法跃迁）。

## 打回路径

| 场景 | 合法跃迁 | 动作 |
|---|---|---|
| 人工审阅 intent 打回 | 停在 `intent` | 继续 grill，回写活文档 |
| spec 被签署人打回 | `spec → intent` | 补裁决后重编译 spec |
| plan 门禁不过 / 切片划不动 | `plan → spec` | 修 spec 需求或验收标准 |
| loop 中发现规划失效 | `loop → plan` | 重编译 plan，归档当前 attempt |
| 收尾后被打回 | `done → loop` | 重开切片 |
