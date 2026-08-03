#!/bin/sh
# ADR loop runner 启动器模板（host=tmux 时在 tmux 内运行）。
# 用法: launch-runner.sh <slice>   例: launch-runner.sh f1
#
# 仅当执行宿主 host=tmux 时使用本脚本。
# 若进入 loop 时探测到 Orca 环境（host=orca），改用 orca-cli 扇出 agent，
# 见 references/orca-host.md —— 不要在本脚本里模拟 Orca。
#
# 复制到 <worktree>/.adr/<id>/run/launch-runner.sh 后改五处：
#   1. ADR_ID= ADR 目录名
#   2. WT= worktree 绝对路径
#   3. IMPL= 实现子进程名称（claude-code / codex / grok；默认 claude-code）
#   4. 代理段（不需要代理可整段删除）
#   5. IMPL 命令（claude-code / codex / grok 三选一，见文末）
# 点火可用 sh "$WT/.adr/$ADR_ID/run/launch-runner.sh" <slice>；chmod +x 后也可直接执行。
# tmux session 建议命名为 adr-${ADR_ID}-<slice>，避免多 ADR 并发撞名。
#
# 无人值守要点：
#   - tmux 新 session 不继承 shell 环境：PATH 显式写、cd 显式做
#   - 不走任何可能交互式 read 的 shell 别名（如 run_with_proxy）
#   - stream-json 日志 tee 落盘，哨兵靠它判进展
#   - GOAL 文件包含工具 goal 指令 + 阶段提示词，runner 原样消费
#   - runner 只写交付报告；验收报告由后续跨工具 reviewer 写（默认 ≠ IMPL）
#   - 对抗验收：impl=claude-code → reviewer 默认 codex 或 grok（见 SKILL.md 配对表）
set -eu
ADR_ID='<id>'
WT=/abs/path/to/worktree
IMPL=claude-code
SLICE="${1:?usage: launch-runner.sh <slice>}"

# ── 1/2. ADR ID 与 worktree 绝对路径（必改）─────────────────
cd "$WT"

export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# ── 3. 实现子进程名称（必改；验收请用另一工具，勿复用本脚本冒充对抗）──
# REVIEWER 仅作记录/环境提示；实际验收由主会话按 SKILL.md 另启 reviewer CLI
# REVIEWER=codex

# ── 4. 代理（按需保留/删除）─────────────────────────────────
# P=http://127.0.0.1:7890
# export http_proxy="$P" https_proxy="$P" HTTP_PROXY="$P" HTTPS_PROXY="$P"
# export all_proxy=socks5h://127.0.0.1:7890 ALL_PROXY=socks5h://127.0.0.1:7890
# NP="localhost,127.0.0.1,::1"
# 需要直连内网/公司域时，再按环境追加域名后缀，例如：
# NP="$NP,.example.com,.corp.example"
# export no_proxy="$NP" NO_PROXY="$NP"

GOAL="$WT/.adr/${ADR_ID}/next-goal.md"
LOG="$WT/.adr/${ADR_ID}/run/${IMPL}-${SLICE}.log"
REPORT="$WT/.adr/${ADR_ID}/run/${IMPL}-${SLICE}-report.md"
export ADR_LOOP_REPORT="$REPORT"

# ── 5a. impl = claude-code（默认）───────────────────────────
claude -p \
  --permission-mode bypassPermissions \
  --verbose --output-format stream-json \
  < "$GOAL" 2>&1 | tee "$LOG"

# ── 5b. impl = codex（用这段时注释掉 5a/5c）────────────────
# 优先 workspace-write 沙箱并从 stdin 读取 goal；--full-auto 仅作旧版兼容。
# codex exec --sandbox workspace-write --json - < "$GOAL" 2>&1 | tee "$LOG"

# ── 5c. impl = grok（用这段时注释掉 5a/5b）─────────────────
# headless 不读 stdin，必须用 --prompt-file；streaming-json 供哨兵 tail
# grok --prompt-file "$GOAL" \
#   --permission-mode bypassPermissions \
#   --output-format streaming-json \
#   2>&1 | tee "$LOG"
