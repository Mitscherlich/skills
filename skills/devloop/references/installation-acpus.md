# 安装与检查 Acpus（可选）

只有显式选择 `--mode acpus` 的新任务使用 Acpus；未指定模式的新任务和无 `execution_mode` 字段或原值为 `default` 的旧任务均使用 `host`。安装了 Acpus 也不会自动切换。devloop 不自动安装、升级或启动第三方服务。

## 安装

按 [Acpus 官方安装说明](https://github.com/kelvinschen/acpus) 安装 npm 包。先检查 Node.js/npm 和当前包的运行环境要求，再选择版本：

```bash
node --version
npm --version
npm view acpus version engines --json
npm install --global acpus
acpus --version
acpus skill read
```

2026-10-20 已实测 Acpus **0.16.1**，Node **24.15.0**；该版本要求 Node `^22.18.0 || >=24.0.0`。复现可用 `npm install --global acpus@0.16.1`，完整证据及限制见 [端到端验证记录](validation-acpus.md)。首次验证可用后，将实际版本写入 plan/progress；不把命令存在性检查当成所有版本兼容承诺。全局 npm 安装遵守所在环境的安装授权规则。

本集成采用 **TypeScript Workflow** 命令族：`workflow check/run`、`runs inspect`、`skill read`。旧版 YAML workflow、`workflows` 等命令族不属于此适配。遇到不兼容版本先查对应发行说明，在没有活动 Run 的环境验证升级；不要对正在运行的任务直接更换 CLI/Runtime。

## devloop 环境检查

```bash
<skill>/scripts/devloop doctor --mode host
<skill>/scripts/devloop doctor --mode acpus
<skill>/scripts/devloop detect-mode --dir .devloop/<id>
# 安装在非标准 PATH 时，可单独检查指定可执行文件
<skill>/scripts/devloop detect-mode --mode acpus --acpus-cli /absolute/path/to/acpus
```

- `host`：报告 Acpus 是否在 PATH 上，不执行它，不因缺少 Acpus 而失败；原有宿主检查保持不变。
- `acpus`：要求可执行文件存在、`--version` 成功且非空，探测 `skill read`、`workflow check/run`、`runs inspect/pause/resume/fork` 的 `--help`，再执行原生 `acpus doctor`。失败返回非零，输出安装文档位置，不回退到 host；此模式不要求 tmux/Orca。
- `acpus_status`：`missing` 未找到；`present` 仅检查到安装；`broken` 版本命令失败；`incompatible` 必要命令探测失败；`unhealthy` 原生 doctor 失败；`ok` 上述检查通过。`unhealthy` 时直接运行 `acpus doctor` 查看诊断。帮助命令可能宽松处理未知参数，仍需实际 `skill read` 和 workflow 检查。
- `acpus_agents_status=unchecked`：CLI/Runtime 健康检查不启动 Agent，不能证明 ACP 适配器、认证、模型请求或结构化输出可用；首次执行前必须完成下面的真实探针。

`--acpus-cli` 只指定本次检查的路径，不修改 PATH，也不为后续运行保存命令别名。后续 Acpus 命令必须使用相同可执行文件和版本。

## Agent 与执行环境

每个任务先阅读一次本机 `acpus skill read`，按该版本的指南配置实现和验收所需的 ACP agent/profile。核对底层工具已安装、认证与额度可用、模型和权限符合 plan、工作目录可访问。实现与验收默认使用不同工具；安装两个同工具实例不等于独立跨工具验收。

**CLI 安装与 ACP 适配器安装是两件事。** 0.16.1 的内置 `codex` / `claude` 使用 npx 启动各自适配器。首次下载可能超过 ACP 初始化窗口；中断下载还可能留下缺少平台二进制的缓存。已获安装授权时，可按该 CLI 内置的版本范围先预热依赖：

```bash
npm exec --yes --package='@agentclientprotocol/codex-acp@^2.0.1' -- node -e 'console.log("Codex ACP dependencies ready")'
npm exec --yes --package='@agentclientprotocol/claude-agent-acp@^0.84.0' -- node -e 'console.log("Claude ACP dependencies ready")'
```

其它 CLI 版本先核对其内置范围，不直接照搬。不要用适配器 `--help` 作为就绪证明：本次实测 Codex 适配器的子进程启动失败仍可能返回 0，Claude 适配器可能等待协议输入。预热也不能代替真实探针。

在独立临时 workspace，用 `ACPUS_HOME=/绝对路径/测试数据` 隔离运行数据；0.16.1 默认数据位于 `~/.acpus/workspaces/...`，不能仅靠更换 cwd 推断完全隔离。每次操作都保持同一 `ACPUS_HOME` **及** workspace cwd。先让所选 impl/reviewer 各返回一个带 outputSchema 的短 JSON，再用 assert 检查值；验证启动、真实模型响应、结构化交接和失败退出。探针也会调用模型，按已授权的测试范围执行。

已验证的排障入口：

- `Missing optional dependency @openai/codex-darwin-arm64`：修复报错所指 ACP 安装的可选依赖，不覆盖已有可用 Codex。也可在已选 Agent 定义的 `env` 中显式设置 `CODEX_PATH` 为已验证的本机 Codex 绝对路径。该变量由 Codex ACP 支持；更换启动环境后须重新做探针。
- `output_framing`：用 `runs artifacts --target <agent>` 找到 `turn-*.json`，查看完整 `finalResponse`。本次 Claude Code 的 auto 模式在 `</ACPUS_OUTPUT>` 后追加网关警告，导致合法 JSON 也被拒绝。在该任务的 Claude 工作目录，将 `.claude/settings.local.json` 的 `permissions.defaultMode` 合并为 `default` 后重试通过；保留其它设置，不全局改用户偏好。Acpus 的 `approve-reads` 与 Claude 自身的 auto/default 模式是不同层，前者不会覆盖后者。不得通过忽略尾部输出、伪造 acceptance 或放宽门禁绕过失败。
- `session_checkpoint_unknown`：0.16.1 在模型响应期间暂停后，可能无法确认旧会话终态，直接 resume 会以 `terminal_unknown` 失败。这是有意拒绝不安全的会话连续执行；不能通过反复 resume/retry 或修改 Runtime 数据解决。核对旧 Agent 已停止、工作树和副作用后，按 [恢复规程](acpus-mode.md#4-中途可见可干预) 从受影响节点 fork 新 Run，保留旧 Run 证据、累计预算和已完成结果的引用。

环境检查不调用模型、不验证账号额度或真实 agent 会话，也不创建 Run。先在临时工作目录用无业务副作用的最小 workflow 验证安装及恢复能力，再运行真实任务。自动化读取运行状态应使用该版本提供的包 API 或 MCP；官方 [CLI 契约](https://github.com/kelvinschen/acpus/blob/main/specs/cli-spec.md) 将 CLI 输出定义为人类可读文本，不应由脚本解析它来决定验收或重试。

## 故障处理

找不到命令时检查安装输出与 PATH；版本命令失败时检查 Node.js 与包的 engines；接口不匹配时读取本机指南并核对版本。提交结果不明时先检查原 Run，禁止直接重提同一批任务。安装修复不应删除 Runtime 数据或现有工作树。执行及观测流程见 [acpus-mode.md](acpus-mode.md)。

与 Herdr 终端的包装边界见 [Acpus 与 Herdr 调研](acpus-herdr.md)。
