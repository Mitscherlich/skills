# @m9ch/skills

可复用的 Claude Code 技能（Skills）集合，为 AI 编程助手提供特定领域的专业能力扩展。

## 安装

通过 [skills cli](https://github.com/vercel-labs/skills) 一键安装全部技能：

```bash
npx skills add Mitscherlich/skills --all
```

安装单个技能：

```bash
npx skills add Mitscherlich/skills --skill <skill-name>
```

## 技能列表

| 技能 | 版本 | 说明 |
|------|------|------|
| [commit-push](./skills/commit-push) | 0.1.0 | 规范化的 git 提交与推送工作流，自动分析变更并生成 Conventional Commits 提交信息 |
| [xmind](./skills/xmind) | 0.2.0 | XMind 思维导图的解析、创建和更新，支持 XMind 8 与 Zen/2020+ 格式互转 |

## 许可

MIT
