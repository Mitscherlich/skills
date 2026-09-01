# next-goal.md 编译手册

**结构契约在 `templates/next-goal.md`**（本 skill 的权威模板，`devloop init --stage next-goal` 可落盘）。本文件只讲**怎么派 goal 编译子代理**。

`next-goal.md` 是 `plan.md` 某一行的展开，不是第二份计划。职责边界见 `references/pipeline.md` 的「阶段 4」表——冲突时一律以 plan.md 为准。

goal 必须**自包含**：runner 是全新 session，没有任何对话上下文，它需要知道的一切要么写在 goal 里，要么是 goal 明确指向的可读文件路径。

## 「工具 goal 指令」段

七字段句式**已内联在 `templates/next-goal.md` 里**：**目标 / 验证 / 约束 / 边界 / 迭代策略 / 完成条件 / 暂停条件**，每行一个 `字段：内容`，照着句式填即可，`devloop gate goal` 会逐行校验这七个字段。

开源 skill [`qiaomu-goal-meta-skill`](https://github.com/joeseesun/qiaomu-goal-meta-skill)（MIT，作者：向阳乔木）是**可选增强**，不是依赖：它擅长把模糊描述打磨成更锐利的 goal 措辞（尤其是验证命令与暂停条件的收敛）。装了就用它产出、再按七字段句式写入该段；没装照模板填，门禁一样通过，二者对 gate 完全等价。安装：`npx skills add joeseesun/qiaomu-goal-meta-skill`。

**其余段落（阶段提示词、代码锚点、分阶段任务、DoD、验收 checklist、BLOCKED 条件）始终按 `templates/next-goal.md` 补齐**，这一段只覆盖七字段。

## 派活 prompt 必须包含的要点

1. **目标写入路径的绝对路径原文**（执行 worktree 内的 `.devloop/<id>/next-goal.md`），并要求写完自检路径正确。
   ⚠️ 这是最高频的翻车点——写到主仓会让 runner 读到旧 goal 然后困惑退出。
2. 让子代理**先读**：`spec.md` 本片覆盖的 `R<n>` 原文、`plan.md` 该片行与统一 DoD、相关裁决 `I-<n>`、上一片报告、涉及的现状代码。
3. 代码锚点要精确到 `file:line`——runner 省下的每一分钟勘察时间都是钱。
4. 「不要做其他事情」——编译子代理**只产出 goal**，不改代码、不提交、不点火。
5. 把「runner 只实现本片，状态推进交给验收」写进 goal，防止 runner 抢跑下一片。
6. next-goal.md 必须同时包含「工具 goal 指令」与「阶段提示词」，runner 将原样消费整个文件。
7. re-open 或重试前先把旧 report/acceptance 归档到 `run/archive/<旧 attempt_id>/`（`devloop attempt archive`），再生成新 attempt；固定旧文件不得充当完成哨兵。
8. 写完 goal 后按约定口径计算 `GOAL_SHA256`：**删除 `GOAL_SHA256:` 整行后**对最终文件计算 SHA-256（避免自引用），把该值同步给 report 与 acceptance。
9. `SPEC_SHA256` / `PLAN_SHA256` 取自 `devloop gate spec` / `devloop gate plan` 通过时输出的 `sha256=`——若取不到，说明上游门禁没过，不该编译 goal。

## 完成标准

`next-goal.md` 已存在于**执行 worktree 内的正确路径**，包含工具 goal 指令、阶段提示词、代码锚点、分阶段任务、统一 DoD、验收 checklist、完成条件、暂停条件与报告路径，且没有 `{{...}}` 占位符残留。

最后必须过门禁，退出码 0 才算编译完成：

```sh
devloop gate goal --file .devloop/<id>/next-goal.md --spec .devloop/<id>/spec.md --plan .devloop/<id>/plan.md
```
