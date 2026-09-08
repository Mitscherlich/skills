# devloop 管线与签署契约（0.7）

阶段产物仍为 intent → spec → plan → goal。**joint 合并人的 spec/plan 审阅时点，保留各自正式门禁。** `review_mode: joint` 写在新 intent 头部；`separate` 或旧文件无字段时逐阶段签署。

## 问题何时解决

| 类型 | 责任与出口 |
|---|---|
| 目标、范围、成功标准、硬约束冲突 | intent 裁决；本阶段阻塞 |
| 仓库实现、接口与依赖事实 | Agent 查证；不能让用户猜事实 |
| 可逆技术方案、设计风险 | spec 展示推荐与证据，联审解决 |
| 执行环境、凭据、切片依赖 | plan 记录负责人、完成条件和被阻塞切片；依赖满足前不点火 |
| 发布授权、环境、观察窗口 | plan 标明发布前置条件，收尾准备发布交接 |

intent 的 `## 未决问题`：未分类的 `- [ ]` 一律阻塞。后续事项使用精确格式：

```markdown
- [ ] [stage=spec] [owner=技术负责人] [due=设计联审前] Q1：核对协议复用边界与验收方式
- [ ] [stage=impl] [owner=环境负责人] [due=F3 点火前] Q2：真实 E2E 凭据可用，否则 F3 paused
```

stage 只接受 spec / plan / impl / release；owner 和 due 均非空。due 说明具体门禁或切片，不写含糊的「以后」。业务红线不能通过标记后移规避；这需要语义审阅，CLI 不自动分类。

编译 spec 时逐项引用 Q ID：解决结果进入设计/关注点，后续条件明确转入 plan。进入 loop 前审阅 Q→结果/阻塞切片的完整覆盖。已由用户裁决的非目标也有价值，但不能为了过门禁把原承诺降级。

## 门禁和下一步

| 命令 | 核对范围 |
|---|---|
| `gate intent` | 核心小节、无内容占位符、编号决定、本阶段无阻塞、后移问题有归属、人工审阅 |
| `gate spec --intent ...` | R 表、设计、无问答历史、关注点已裁决、签署、上游 hash |
| `gate plan --spec ...` | roadmap、逐条 R 覆盖、引用的 F 存在、状态、执行确认、上游 hash |
| `gate goal --spec ... --plan ...` | 七字段、header、自 hash、上游绑定；保持原点火契约 |

前三个命令可加 `--draft`：只豁免签署区占位符和签署校验；spec 草稿可保留需联审解决的关注点。输出 `mode=draft`、`approval=not_checked`，退出 0 只说明草稿结构可用于准备下一份材料。**goal 不接受 --draft。**

`next --dir`：

- intent 内容未完成或被打回 → `grill_intent`；仅缺审阅 → `await_intent_review`。
- intent 正式通过 → `compile_spec`。
- spec 草稿内容不合格或被打回 → `fix_spec`；separate 缺签署 → `await_spec_review`；joint 草稿合格 → `compile_plan`。
- plan 草稿不合格或被打回 → `fix_plan`；仅缺签署 → `await_design_review`（joint）或 `await_plan_review`（separate）。
- 三份正式通过 → 切片动作；全部 done → `finalize`。finalize 是收尾请求，不能证明验收证据齐备。

## 编译 spec

编译者读取已确认 intent、当前仓库与 AGENTS/CLAUDE/领域规范，写 `templates/spec.md`：

1. 每条 R 有可执行或可观察的验收标准和 I 来源，需求保留稳定 ID。
2. 设计只写当前选择，保留关键理由；问答历史留 progress。当前决定改变后，同步 intent 正文和引用它的内容，不能只在尾部追加相反裁决。
3. 技术深化若未改变目标/硬边界，留在 spec；改变业务承诺或允许写入范围才回 intent 做增量裁决。
4. `## 关注点与冲突` 中尚需用户选择的内容用 `- [ ] C1：...`；解决后改为 `- [x] C1：决定及理由`。正式 gate 拦截此处未勾选项。表格中也只保留已生效选择。
5. 记录 `intent_sha256`，只写 spec，不改业务代码或代签。

## 编译 plan

用 `templates/plan.md`，输入为 spec、intent 后续事项和现状代码：

- 给每条 R 映射 F；按一次独立 runner 可交付且可验证的切片拆分。依赖单向、每次至多一个 open。
- 优先安排最薄的真实链路，早暴露接口/环境约束；有凭据前置的切片明确 paused，其余独立切片可继续。保留最终整体验证。
- 后续问题进入「执行前置条件」，每项标 Q ID、负责人、满足证据和阻塞切片/发布动作。主会话编 goal 前核验。
- 按 [知识维护协议](knowledge.md) 填「相关项目知识」；编译 spec 时同样按索引读取本轮适用资料。
- 确认记录包含范围、host/impl/reviewer、权限、source worktree/base、控制面与规格/知识归位范围、清理边界。能探测的选项自动填写；权限例外由真实授权支持。
- 切片状态为 open / pending / done (...) / paused(...)。plan 是切片状态唯一事实源，goal 不推进它。

## 联审和 hash 封存顺序

1. 先运行 intent 正式门禁、spec/plan 草稿门禁。联审摘要指向两份草稿全文，显示关键取舍、前置条件和授权范围。
2. 在 progress 留下本次提交用户审阅的 spec/plan 原始文件 hash；将用户实际确认消息或外部审批 ID、范围和时间作为来源。没有答复不能填「通过」。明确打回时修订，不重复请求同一版本签字。
3. 用户确认的内容不变时，先填写 spec 签署元数据，跑正式 B 得到最终 spec hash；再填写 plan 的 `spec_sha256` 和确认元数据，跑正式 C。这一步只同步签署/绑定元数据，不需要让用户再次审阅同一语义内容。
4. 若任一业务内容变更，则展示差异、核对影响、重新取得所需确认并重编译受影响下游。禁止用直接替换 hash 掩盖内容漂移。
5. plan 的「进入 loop 结论」使用 `通过` / `确认进入` / `同意进入`，原话放另一个来源字段。确认 plan 的自 hash 存 progress 或交接记录，**不要把整份文件的 hash 写回自身造成自引用**。
6. 签署封存后按 [知识维护协议](knowledge.md) 将定稿需求合并到 `docs/knowledge/specs/`，保留本轮签署原件和绑定；需求定稿与实现验收分开记录。执行前再次运行三个正式门禁、核对真实授权及前置条件，再按 [loop.md](loop.md) 点火。签署文本不是身份认证，CLI 的通过不替代语义和授权核验。

## Goal 与打回

goal 沿用 [goal-template.md](goal-template.md)；只引用 spec/plan，逐 attempt 生成，完整复制统一 DoD。上游正文变化需要重新编译，所有报告和 acceptance 都绑定本轮 goal 与 commit。

阶段转移仍是 intent → spec → plan → loop → done。草稿编译不是执行授权。打回使用 spec→intent、plan→spec、loop→plan、done→loop；新的业务目标创建新 ID，并记录 parent_devloop 与来源。

访谈的 design tree / frontier 思路沿用原版对 [mattpocock/skills 的 grilling](https://github.com/mattpocock/skills)（MIT）的改写；0.7 将准出范围收窄到本阶段阻塞问题。
