# Control-plane CLI 契约（0.9.1）

统一入口 `<skill>/scripts/devloop`。先用 `next --dir` 决定动作；规程通过 SKILL.md 的条件链接按需读取。

| 命令 | 行为 | 退出码 |
|---|---|---|
| `setup [--project DIR] [--check]` | 创建知识/规格索引、AGENTS 入口和过程忽略规则；--check 只读检查入口和 specs Git 可见性，不检查语义/索引链接。默认当前 Git worktree 根目录，否则 cwd；显式 --project 精确指定目录 | 0 已初始化 / 1 缺入口或操作失败 / 2 参数错误 |
| `init --id ID [--title T] [--root DIR] [--stage S] [--force]` | 默认建 intent/progress/run；S 可为 intent/spec/plan/next-goal/progress/closeout；维护控制面内 .gitignore，仅忽略过程材料并迁移可识别旧规则，保留已跟踪文件原状；对目标 worktree（非 Git 为 root 父目录）只读检查知识入口，缺入口仅提示 setup | 0 成功 / 1 拒绝覆盖或失败 |
| `gate intent --file PATH [--draft]` | 意图结构、本阶段阻塞与后续归属、审阅；新模板 joint，旧文件无模式为 separate | 0 通过 / 1 未通过 / 2 输入错误 |
| `gate spec --file PATH [--intent PATH] [--draft]` | R 表、设计、过程残留、关注点、签署、上游 hash | 同上 |
| `gate plan --file PATH [--spec PATH] [--draft]` | 切片状态、R→F 全覆盖、确认、上游 hash | 同上 |
| `gate goal --file PATH [--spec PATH] [--plan PATH]` | 点火前结构、自 hash、上游绑定；拒绝 --draft | 同上 |
| `next --dir DIR` | 完整管线动作；await_* 是等审阅，finalize 是请求核对收尾 | 0 / 输入错误非零 |
| `next --plan PATH [--run-dir DIR]` | 仅投影切片下一步；不替代全管线与验收检查 | 同上 |
| `status --plan PATH [--json]` | 切片状态计数；多 open 非法 | 0 / 1 |
| `review-packet --devloop-dir PATH` | 展示正式门禁、状态、next、报告数量和摘要；非验收报告 | 0 |
| `stage validate\|can\|transitions --from S [--to S]` | 管线合法转移查询，无持久化副作用 | can: 0 合法 / 1 拒绝 |
| `state validate\|can\|transitions --from S [--to S]` | 切片合法转移查询 | 同上 |
| `attempt new\|archive ...` | 新 attempt / 运行目录内部旧报告搬移；仅保留本轮重试证据，与持久规格归位无关 | 0 / 1 |
| `lock acquire\|release\|check --run-dir D --phase P` | mkdir 阶段锁：compile/impl/review/advance | acquire: 0 获得 / 1 忙 |
| `detect-host ...` / `detect-scheduler ...` | 探测 host 与调度能力 | 见对应 --help |
| `cleanup-sessions ...` | 仅关闭指定 worktree 的已完成 session，保留 keep 集合 | 0 / 非零失败 |
| `doctor` / `run-tests` | 安装自检 / 全部 tests/*.test.sh | tests: 0 全绿 / 1 失败 / 2 无测试 |

## 草稿和正式门禁

`--draft` 输出 `mode=draft` / `approval=not_checked`；只豁免签署区的待签字段和签署校验，仍校验正文与传入的上游 hash。它不能授权 runner、代签或用于宣布验收通过。字段 sha256 仍为原始文件完整 hash，用来准备下游草稿。

正式门禁的 `mode=full` 不代表身份认证。协调者仍要核对实际用户确认来源与语义一致性。联合签署的元数据封存顺序见 [pipeline.md](pipeline.md)。

## 两套状态机

- 管线：intent → spec → plan → loop → done；打回 spec→intent / plan→spec / loop→plan / done→loop。
- 切片：pending → open → implementing → reviewing → done；支持 paused 和 re-open，见 `state transitions`。

plan 是切片状态事实源；收尾不新增一套状态数据库。发布状态与下一轮候选记在 closeout，实际发布凭据在项目既有平台。新一轮创建新 ID，并引用 parent 与候选来源，不把旧 done 重解释成新任务。

## 依赖与限制

核心沿用 POSIX sh、git、awk/sed、SHA 工具。本版不含跨会话 daemon 或发布平台。运行协议见 [loop.md](loop.md)，收尾与旧流程处理见 [closeout.md](closeout.md)。

`archive --dir --output` / `archive --verify` 外部整包方案已移除；CLI 返回迁移提示，不再打包。用 skill 按 [知识维护协议](knowledge.md) 将定稿需求合并到持久 specs，收尾将其它内容分别归位。
