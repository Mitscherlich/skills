#!/bin/sh
# ADR loop runner 启动器模板（在 tmux 内运行）。
# 用法: launch-runner.sh <slice>   例: launch-runner.sh f1
#
# 复制到 <worktree>/.adr/<id>/run/launch-runner.sh 后改四处：
#   1. WT= worktree 绝对路径
#   2. IMPL= 实现子进程名称（claude-code / codex / grok；默认 claude-code）
#   3. 代理段（不需要代理可整段删除）
#   4. IMPL 命令（claude-code / codex / grok 三选一，见文末）
#
# 无人值守要点：
#   - tmux 新 session 不继承 shell 环境：PATH 显式写、cd 显式做
#   - 不走任何可能交互式 read 的 shell 别名（如 run_with_proxy）
#   - stream-json 日志 tee 落盘，哨兵靠它判进展
#   - GOAL 文件包含工具 goal 指令 + 阶段提示词，runner 原样消费
#   - runner 只写交付报告；验收报告由后续跨工具 reviewer 写（默认 ≠ IMPL）
#   - 对抗验收：impl=claude-code → reviewer 默认 codex 或 grok（见 SKILL.md 配对表）
set -eu
SLICE="${1:?usage: launch-runner.sh <slice>}"

# ── 1. worktree 绝对路径（必改）──────────────────────────────
WT=/abs/path/to/worktree
cd "$WT"

export PATH="/opt/homebrew/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# ── 2. 实现子进程名称（必改；验收请用另一工具，勿复用本脚本冒充对抗）──
IMPL=claude-code
# REVIEWER 仅作记录/环境提示；实际验收由主会话按 SKILL.md 另启 reviewer CLI
# REVIEWER=codex

# ── 3. 代理（按需保留/删除）─────────────────────────────────
# P=http://127.0.0.1:7890
# export http_proxy="$P" https_proxy="$P" HTTP_PROXY="$P" HTTPS_PROXY="$P"
# export all_proxy=socks5h://127.0.0.1:7890 ALL_PROXY=socks5h://127.0.0.1:7890
# NP="localhost,127.0.0.1,::1"
# 需要直连内网/公司域时，再按环境追加域名后缀，例如：
# NP="$NP,.example.com,.corp.example"
# export no_proxy="$NP" NO_PROXY="$NP"

GOAL=".adr/<id>/next-goal.md"
LOG=".adr/<id>/run/${IMPL}-${SLICE}.log"
REPORT=".adr/<id>/run/${IMPL}-${SLICE}-report.md"
export ADR_LOOP_REPORT="$REPORT"

# ── 4a. impl = claude-code（默认）───────────────────────────
claude -p \
  --permission-mode bypassPermissions \
  --verbose --output-format stream-json \
  < "$GOAL" 2>&1 | tee "$LOG"

# ── 4b. impl = codex（用这段时注释掉 4a/4c）────────────────
# codex exec --full-auto --json "$(cat "$GOAL")" 2>&1 | tee "$LOG"

# ── 4c. impl = grok（用这段时注释掉 4a/4b）─────────────────
# headless 不读 stdin，必须用 --prompt-file；streaming-json 供哨兵 tail
# grok --prompt-file "$GOAL" \
#   --permission-mode bypassPermissions \
#   --output-format streaming-json \
#   2>&1 | tee "$LOG"
