# Acpus 是否能用 Herdr 包装 agent

2026-10-21 查证：本机 Herdr **0.9.5**；Acpus 上游源码 commit `59739f52cd93e5c25c4dae3c8beadd006343d133`。本机当前 PATH 无 acpus，以下是源码与 CLI 契约研究，未做真实模型端到端验证。

**结论：可以在 Herdr 终端中运行 Acpus 协调命令，但不能直接把 `herdr pane run` / `agent attach` 当作 Acpus 的 agent command 包装器。** 未发现现成的 Herdr ACP stdio 桥接接口，因此 devloop 不提供 `--mode acpus --host herdr`。

- Acpus 支持自定义 agent 启动命令；[ACP transport 源码](https://github.com/kelvinschen/acpus/blob/59739f52cd93e5c25c4dae3c8beadd006343d133/packages/acp/src/transport.ts#L120) 将子进程 stdin/stdout/stderr 设为 pipe，并直接将 stdin/stdout 连接到 `ndJsonStream`。启动命令必须持续承载双向 ACP 协议，并保留退出、取消和恢复语义。
- 本机 `herdr pane run --help` 定义为在指定 pane 中执行命令；`herdr agent attach --help` 是附着交互终端。它们管理 PTY/终端会话，不承诺调用方 stdin/stdout 为原始 ACP 协议流。把命令换成这些 CLI，不能满足 Acpus 的传输合同。
- 可行的外层使用方式：在 Herdr pane 中执行 `acpus workflow run ...` 或只读查看 runs/artifacts；内部 ACP agent 仍由 Acpus 管理。Herdr 的 pane 生命周期不能替代 Runtime 的 Run/节点状态。
- 若要求每个 ACP agent 都在 Herdr pane 内运行，需要额外桥接原始双向协议、进程退出及信号，并验证 pause/resume/fork 后的会话绑定。仅能填写自定义 command 不足以证明支持；本次不实现该桥接。

复核入口：`herdr --version`、`herdr pane run --help`、`herdr agent attach --help`；升级后重新核对 [Acpus 上游](https://github.com/kelvinschen/acpus) 与本机 `acpus skill read`。
