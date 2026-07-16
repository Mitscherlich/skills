# next-goal.md 模板（.adr/<id>/next-goal.md）

goal 编译 agent 的输出结构（**本 skill 的权威契约**）。goal 必须**自包含**——runner 是全新 session，没有任何对话上下文，所有它需要知道的都要写在这里或指向可读文件。文件顶部必须是可被实现工具消费的 goal 指令，后面跟阶段提示词。

「工具 goal 指令」段推荐用开源 skill [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT）生成；未安装时按下方字段手写等价内容即可。安装：`npx skills add joeseesun/qiaomu-goal-meta-skill`。

```markdown
# next-goal

STATUS: open
SLICE: <F2>
TASK: ADR <id> · <切片名>（<一行范围摘要>）

## 工具 goal 指令

<推荐：用 qiaomu-goal-meta-skill 产出的 goal 指令原样写入；或手写等价结构。必须包含：目标、验证、约束、边界、迭代策略、完成条件、暂停条件。>

## 阶段提示词

> **权威依据**（动手前先完整阅读）：
> 1. `.adr/<id>/plan.md` —— 本片行 + 统一 DoD + 循环协议
> 2. <相关设计文档/ADR 路径> —— 决策 <N>
> 3. `.adr/<id>/run/<impl>-<上一片>-report.md` —— 上一片交付了什么

## 现状代码锚点（精确 file:line）

| 锚点 | 位置 | 现状 | 本片目标 |
|------|------|------|---------|
| <关键类/函数> | `src/foo.ts:120-148` | <现在长什么样> | <改成什么样> |

## 分阶段任务清单

### 阶段 1：<名>
1. <文件路径>：<具体动作>
2. ...

### 阶段 2：<名>
...

## 设计约束（不可破）

- <项目红线，如：某层不得持有某权限 / 某接口不得加某字段>
- 只能实现本切片；不得推进下一片或修改 roadmap 状态。
- 本地 commit，**绝不 push**
- runner 退出前必须写报告；若遇到 BLOCKED 条件，报告写明 `BLOCKED`、证据和需要的人类决策。
- runner 自报完成不等于阶段完成；阶段完成只能由验收子代理在 acceptance 报告中给出 `全部完成`。

## 统一 DoD

<从 plan.md 原样复制>

## 验收 checklist

- [ ] <可 grep/可跑命令验证的具体断言>
- [ ] 门禁全绿：<命令> → <期望数字>
- [ ] commit `feat(adr<id>-<slice>): ...` 产生
- [ ] 报告写 `.adr/<id>/run/<impl>-<slice>-report.md`
- [ ] 等待验收子代理写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`，runner 不自行推进状态
- [ ] 没有修改 plan.md 的切片状态；状态推进只由核验步骤完成

## BLOCKED 条件（满足即停、报告写明）

1. <语义歧义示例>
2. 门禁 3 轮修复不过
3. 需要外部凭据：<具体是什么>
```

## goal 编译 agent 的 prompt 要点

派 goal 编译 agent 时，prompt 必须包含：

1. **目标写入路径的绝对路径原文**（worktree 内的 `.adr/<id>/next-goal.md`），并要求写完自检路径正确。这是最高频的翻车点——写到主仓会让 runner 读到旧 goal。
2. 让 agent 先读：plan.md 该片行、相关决策原文、上一片报告、涉及的现状代码。
3. 锚点要求精确到 file:line——runner 省下的每一分钟勘察时间都是钱。
4. 「不要做其他事情」——编译 agent 只产出 goal，不改代码。
5. 把「runner 只实现本片，状态推进交给核验」写进 goal，防止 runner 抢跑下一片。
6. next-goal.md 必须同时包含「工具 goal 指令」和「阶段提示词」，runner 将原样消费整个文件。
7. 结构以本模板为准；若会话中可用 qiaomu-goal-meta-skill，仅用它填充「工具 goal 指令」段，其余段落仍按本模板补齐。
