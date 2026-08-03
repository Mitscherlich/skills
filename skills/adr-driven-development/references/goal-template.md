# next-goal.md 模板（.adr/<id>/next-goal.md）

goal 编译 agent 的输出结构（**本 skill 的权威契约**）。goal 必须**自包含**——runner 是全新 session，没有任何对话上下文，所有它需要知道的都要写在这里或指向可读文件。文件顶部必须是可被实现工具消费的 goal 指令，后面跟阶段提示词。

「工具 goal 指令」段推荐用开源 skill [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT）生成；未安装时按下方字段手写等价内容即可。安装：`npx skills add joeseesun/qiaomu-goal-meta-skill`。

```markdown
# next-goal

STATUS: open
SLICE: <F2>
ATTEMPT_ID: <不可复用的 attempt_id>
TASK: ADR <id> · <切片名>（<一行范围摘要>）
PLAN_SHA256: <已确认 plan 的 SHA-256>
GOAL_SHA256: <删除本行后，对最终 goal 全文计算的 SHA-256>
BASE_SHA: <本 attempt 起点 SHA>
HEAD_SHA: <编译 goal 时的 HEAD SHA>

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
- 只暂存本片 allowlist 路径，避免无边界 `git add -A` 把 control-plane 或上一轮 dirty 文件混入 commit。
- runner 退出前必须写报告；报告头记录与 goal 一致的 `attempt_id`、`goal_sha256`、`base_sha` 及提交后的 `head_sha`。先写同目录临时文件，完整落盘后 atomic rename 到报告路径。若遇到 BLOCKED 条件，报告写明 `BLOCKED`、证据和需要的人类决策。
- runner 自报完成不等于阶段完成；阶段完成只能由 **与 impl 不同的 reviewer** 在 acceptance 报告中给出 `全部完成`（host 可为 tmux 或 orca terminal）。
- runner 不得自行启动验收或修改 acceptance 报告。
- reviewer 默认只写 acceptance 并只读复跑测试；acceptance allowlist 外出现新增 diff 必须判 `BLOCKED`。任何同工具验收都须用户明确授权；「只剩一个工具」只触发询问。

## 统一 DoD

<从 plan.md 原样复制>

## 验收 checklist

- [ ] <可 grep/可跑命令验证的具体断言>
- [ ] 门禁全绿：<命令> → <期望数字>
- [ ] commit `feat(adr<id>-<slice>): ...` 产生
- [ ] 报告通过 atomic rename 写 `.adr/<id>/run/<impl>-<slice>-report.md`，header 含 attempt/hash/SHA 绑定
- [ ] 等待跨工具 reviewer 写 `.adr/<id>/run/<impl>-<slice>-acceptance.md`（文件头注明 impl/reviewer/attempt/hash/reviewed head），runner 不自行推进状态
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
8. re-open 或重试前先把旧 report/acceptance 归档到 `run/archive/<旧 attempt_id>/`（或采用含 attempt 的新路径），再生成新 attempt；固定旧文件不得充当完成哨兵。
9. 写完 goal 后按约定口径计算 `goal_sha256`：删除 `GOAL_SHA256:` 整行后对最终文件计算 SHA-256，避免自引用；把该值同步给 report 与 acceptance。
