# @m9ch/skills

## 安装

通过 [skills cli](https://github.com/vercel-labs/skills) 一键安装全部技能：

```bash
npx skills add Mitscherlich/skills --all
```

安装单个技能：

```bash
npx skills add Mitscherlich/skills --skill <skill-name>
```

安装后常见落盘位置（依 CLI / agent 而异）：`~/.agents/skills`、项目内 `.agents/skills`，以及 Claude 的 `.claude/skills` 兼容路径。

## 技能列表

| 技能 | 版本 | 说明 |
|------|------|------|
| [adr-driven-development](./skills/adr-driven-development) | 0.5.0 | ADR 驱动无人值守交付：grill → plan → goal → detect-runtime-host → tmux\|orca impl → 跨工具 reviewer |
| [commit-push](./skills/commit-push) | 0.4.2 | 规范化的 git 提交与推送工作流，自动分析变更并生成 Conventional Commits 提交信息；默认不写 Co-authored-by，需 `--enable-co-authored-by` |
| [iterm2](./skills/iterm2) | 0.1.0 | 通过 iTerm2 Python API 编程控制 iTerm2 终端，支持窗口/标签/面板管理、输入广播、配色字体等 |
| [xmind](./skills/xmind) | 0.2.0 | XMind 思维导图的解析、创建和更新，支持 XMind 8 与 Zen/2020+ 格式互转 |

## 许可

MIT
