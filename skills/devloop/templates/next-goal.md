# next-goal

STATUS: open
SLICE: {{F2}}
ATTEMPT_ID: {{不可复用的 attempt_id}}
TASK: {{id}} · {{切片名}}（{{一行范围摘要}}）
SPEC_SHA256: {{已签署 spec 的 SHA-256}}
PLAN_SHA256: {{已确认 plan 的 SHA-256}}
GOAL_SHA256: {{删除本行后，对最终 goal 全文计算的 SHA-256}}
BASE_SHA: {{本 attempt 起点 SHA}}
HEAD_SHA: {{编译 goal 时的 HEAD SHA}}

## 工具 goal 指令

> 七行字段缺一不可，每行形如 `字段：内容`，`devloop gate goal` 逐行校验。装了 `qiaomu-goal-meta-skill` 可用它生成后按本句式原样写入；没装就直接照下面填，效果等价。

目标：{{本片完成后可观察到的终态，一句话，写结果不写过程，例：`<模块> 支持 <能力>，<入口命令> 对 <输入> 返回 <输出>`}}
验证：{{逐条可复现的证据：可执行命令 `cmd → 期望输出/退出码`、可 grep 的断言、产出物路径；不接受「跑一下看看」}}
约束：{{不允许改变的东西：对外接口签名、数据格式与字段名、既有行为与默认值、依赖与版本；写清「谁不许动」}}
边界：{{允许写入的路径 allowlist（精确到文件或目录）；禁止触碰的路径（至少含 .devloop/ 控制面、plan.md 切片状态、其他切片的代码）}}
迭代策略：{{一次只做一个聚焦改动，改完立刻重跑上面的验证命令；失败先定位再改，不叠加猜测性修改；每轮进展与失败原因追加进报告}}
完成条件：{{出现什么证据即视为完成，例：上面每条验证命令全绿 + 本片 commit 已产生 + 报告已 atomic rename 落盘且 header 绑定本 goal 的 attempt/hash}}
暂停条件：{{满足任一即停、不再重试，并在报告写 BLOCKED + 证据 + 需要的人类决策；必须含预算上限，例：门禁 3 轮修复不过 / 需求语义歧义 / 需要外部凭据 / 超过 N 轮或 N 分钟}}

## 阶段提示词

> **权威依据**（动手前先完整阅读，顺序不可颠倒）：
> 1. `.devloop/{{id}}/spec.md` —— 本片覆盖的需求 {{R 编号}} 原文与验收标准
> 2. `.devloop/{{id}}/plan.md` —— 本片行 + 需求追溯 + 统一 DoD + 循环协议
> 3. {{相关设计文档路径}} —— 裁决 {{I 编号}}
> 4. `.devloop/{{id}}/run/<impl>-{{上一片}}-report.md` —— 上一片交付了什么

## 现状代码锚点（精确 file:line）

| 锚点 | 位置 | 现状 | 本片目标 |
|---|---|---|---|
| {{关键类 / 函数}} | `{{src/foo.ts:120-148}}` | {{现在长什么样}} | {{改成什么样}} |

## 分阶段任务清单

### 阶段 1：{{名}}

1. {{文件路径}}：{{具体动作}}

### 阶段 2：{{名}}

1. {{…}}

## 设计约束（不可破）

- {{项目红线：某层不得持有某权限 / 某接口不得加某字段}}
- 只能实现本切片；不得推进下一片或修改 roadmap 状态。
- 本地 commit，**绝不 push**。
- 只暂存本片 allowlist 路径，避免无边界 `git add -A` 把 control-plane 或上一轮 dirty 文件混入 commit。
- 退出前必须写报告；报告头记录与本 goal 一致的 `attempt_id`、`goal_sha256`、`base_sha` 及提交后的 `head_sha`。先写同目录临时文件，完整落盘后 atomic rename。遇 BLOCKED 条件，报告写明 `BLOCKED`、证据和需要的人类决策。
- runner 自报完成不等于阶段完成；阶段完成只能由**与 impl 不同的 reviewer** 在 acceptance 报告中给出 `全部完成`。
- runner 不得自行启动验收或修改 acceptance 报告。

## 统一 DoD

{{从 plan.md 的「每片统一 DoD」原样复制}}

## 验收 checklist

- [ ] {{可 grep / 可跑命令验证的具体断言}}
- [ ] 覆盖的 spec 需求 {{R 编号}} 的验收标准逐条满足
- [ ] 门禁全绿：{{命令}} → {{期望数字}}
- [ ] commit `feat({{id}}-{{slice}}): …` 产生
- [ ] 报告经 atomic rename 写入 `.devloop/{{id}}/run/<impl>-{{slice}}-report.md`，header 含 attempt/hash/SHA 绑定
- [ ] 等待跨工具 reviewer 写 `.devloop/{{id}}/run/<impl>-{{slice}}-acceptance.md`，runner 不自行推进状态
- [ ] 没有修改 plan.md 的切片状态

## BLOCKED 条件（满足即停、报告写明）

1. {{语义歧义示例}}
2. 门禁 3 轮修复不过
3. 需要外部凭据：{{具体是什么}}
