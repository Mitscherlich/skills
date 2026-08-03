# AGENTS.md

此文件为多 Agent 工具（Codex / Claude Code / Grok / 其他）提供项目级别的上下文和指导规范。

## 项目概述

`@m9ch/skills` 是一个可复用的 AI 技能（Skills）集合仓库。每个技能是一个独立的功能模块，提供特定领域的专业能力，供各类 coding agent 在对话中调用——**不绑定单一厂商**。

## 项目结构

```
skills/                     # 技能源目录（唯一真相源，所有技能存放于此）
├── <skill-name>/           # 单个技能目录
│   ├── SKILL.md            # 技能说明文档（必需）
│   └── scripts/            # 技能脚本（如有）
│       └── *.py / *.sh     # 实现脚本
.agents/
└── skills -> ../skills     # 多 Agent 通用入口（Codex / Grok / 通用 skills 发现路径）
.claude/
└── skills -> ../skills     # Claude Code 兼容入口（与 .agents 指向同一源）
```

约定：

- **改技能只改 `skills/`**；`.agents/skills` 与 `.claude/skills` 均为相对符号链接，禁止在链接目录内另存副本。
- 优先保证 `.agents/skills` 可用，避免技能仅对 Claude 可见。
- 新增 agent 适配时，优先挂 `.agents/skills`，不要再复制一份技能树。

## 技能开发规范

### 目录与文件约定

- 每个技能以独立目录存放在 `skills/` 下，目录名使用 kebab-case（如 `commit-push`、`xmind`）
- 每个技能 **必须** 包含 `SKILL.md` 文件，作为技能的入口文档
- 实现脚本放在技能目录下的 `scripts/` 子目录中

### SKILL.md 格式

每个 `SKILL.md` 必须包含 YAML frontmatter 和详细的技能说明：

```markdown
---
name: <技能名称>
description: <触发词和功能描述>
version: <语义化版本号>
---

# 技能标题

技能详细说明...
```

**Frontmatter 字段说明：**

- `name`：技能的唯一标识名称，与目录名一致
- `description`：描述技能的功能以及触发该技能的关键词/短语
- `version`：遵循语义化版本规范（SemVer）

### 技能实现原则

- **零外部依赖**：脚本应尽量使用标准库，避免引入第三方依赖
- **会话隔离**：涉及临时文件的技能应使用 session ID 隔离数据
- **中文交互**：技能文档和用户交互均使用中文
- **幂等性**：技能操作应尽量保证可重复执行

## 现有技能

| 技能 | 版本 | 说明 |
|------|------|------|
| `adr-driven-development` | 0.3.1 | ADR 驱动无人值守交付（grill → plan → goal → detect-runtime-host → 跨工具 reviewer） |
| `xmind` | 0.2.0 | XMind 思维导图文件的解析、创建和更新 |
| `commit-push` | 0.4.1 | 规范化的 git 提交与推送工作流 |
| `iterm2` | 0.1.0 | 通过 iTerm2 Python API 控制 iTerm2 终端行为 |

## Git 提交规范

提交信息格式遵循 Conventional Commits：

```
<type>[(scope)]: <message>
```

- type：feat / fix / docs / refactor / chore / test / style / perf / ci / misc
- scope（可选）：变更涉及的模块或范围
- message：简明扼要的变更描述

## 开发注意事项

- 不要提交敏感信息（`.env`、密钥文件等）
- 脚本文件应包含 shebang 行（如 `#!/usr/bin/env python3`）
- Python 脚本使用 Python 3 编写
