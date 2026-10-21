# Herdr 执行宿主

仅在 `execution_mode: host` 且 `detect-host` 选中 herdr 时读取。自动选择只要求 `herdr` 在 PATH；执行前运行 `herdr --version`、`herdr status server`，并读取本机 `herdr --skill` 核对当前语法。服务不可用时记录阻塞，按用户已授权范围启动 Herdr 后重试；不静默换宿主。

1. 用 `git worktree add` 创建本轮执行区，显式交接 `.devloop/<id>` 并核对 plan hash。impl 与 reviewer 共用该 checkout。
2. 用 `herdr workspace list` 确定目标 workspace；`herdr tab create --workspace <workspace-id> --cwd <worktree> --label devloop-<id>-<slice>-<attempt> --no-focus` 创建任务 tab，再通过 `herdr pane list` 获取该 tab 的 pane ID。记录 workspace/tab/pane ID，后续操作全部使用返回的 ID，不操作用户其他 pane。
3. 复用 `launch-runner-template.sh` 的输入和报告约定准备 impl 脚本，显式设置 cwd/PATH；用 `herdr pane run <pane-id> sh <runner-script> <slice>` 启动。脚本记录真实 agent 退出码：不能把 `agent | tee` 的 tee 退出码当成 agent 结果；可先重定向日志，捕获退出码，再原子写本 attempt 的 exit 文件。不要把 `pane run` 命令返回当成 agent 已完成。
4. 巡检用 `herdr pane read <pane-id>`、日志、exit 文件、报告及 commit 绑定；pane 存活或 idle 不是验收通过。保持 loop.md 的 attempt/锁/独立 reviewer 边界。
5. impl 完成后，在同一 checkout 的新 tab/pane 运行不同工具的 reviewer，输入 acceptance prompt，保存独立日志和退出码；reviewer 仅写验收报告。验证 reviewed HEAD 与当前 HEAD 一致才能推进切片。
6. 报告与验收证据落盘、进程确认结束后，仅关闭本轮记录的 tab：`herdr tab close <tab-id>`。失败与暂停时先保存现场，不用关闭终端替代停止确认。

这里运行的是普通 CLI agent；Acpus 的 ACP 子进程不通过此路径启动，原因见 [调研记录](acpus-herdr.md)。
