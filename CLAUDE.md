# CLAUDE.md

此文件为 Claude Code 提供项目级别的上下文和指导规范。

## 项目概述

`@m9ch/skills` 是一个可复用的 Claude AI 技能（Skills）集合仓库。每个技能是一个独立的功能模块，提供特定领域的专业能力，供 Claude 在对话中调用。

## 项目结构

```
skills/                     # 技能目录（所有技能存放于此）
├── <skill-name>/           # 单个技能目录
│   ├── SKILL.md            # 技能说明文档（必需）
│   └── scripts/            # 技能脚本（如有）
│       └── *.py / *.sh     # 实现脚本
.claude/
└── skills -> ../skills     # 符号链接，指向技能目录
```

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
| `xmind` | 0.2.0 | XMind 思维导图文件的解析、创建和更新 |
| `commit-push` | 0.2.0 | 规范化的 git 提交与推送工作流 |

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
