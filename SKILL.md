---
name: skill-review
description: Skills/Agents 设计委员会——对 skill/agent 文件进行多维质量审查的 command 包，含协调者 command + 六个专项 Agent（S1/S2/S3/S4/Challenger/Reporter）。安装到 ~/.claude/commands/ 和 ~/.claude/agents/。
---

# skill-review 包

## 包含文件

### Commands（协调者）
- `commands/skill-review.md` → 安装到 `~/.claude/commands/skill-review.md`

### Agents（委员会成员）
- `agents/skill-reviewer-s1.md` → 安装到 `~/.claude/agents/skill-reviewer-s1.md`（定义质量审计）
- `agents/skill-reviewer-s2.md` → 安装到 `~/.claude/agents/skill-reviewer-s2.md`（互动链路审计）
- `agents/skill-researcher.md` → 安装到 `~/.claude/agents/skill-researcher.md`（外部前沿研究）
- `agents/skill-reviewer-s4.md` → 安装到 `~/.claude/agents/skill-reviewer-s4.md`（可用性审计）
- `agents/skill-challenger.md` → 安装到 `~/.claude/agents/skill-challenger.md`（Challenger，opus）
- `agents/skill-reporter.md` → 安装到 `~/.claude/agents/skill-reporter.md`（Reporter，含 Edit 权限）

## 委员会结构

```
/skill-review <target>
        │
Stage 1 │  ┌──────────────────────────────────────────────────┐
（并行）  │  │  S1 定义质量  S2 链路审计  S3 外部研究  S4 可用性  │
        │  └──────────────────────────────────────────────────┘
        │                    ↓ 汇总 ↓
Stage 1 │  展示发现摘要，等待用户确认进入 Stage 2
中场    │
        │
Stage 2 │  Challenger（opus）── 反驳性验证 P0/P1 发现
（串行）  │        ↓
        │  Reporter（sonnet，含 Edit）── 报告 + 直接修复
        │
Stage 3 │  Grader（可选）── 断言设计（description 变更时触发）
（条件）  │
```

## 模型分配

| 成员 | 模型 | 原因 |
|------|------|------|
| S1/S2/S4 | sonnet | 文档分析，无需高成本推理 |
| S3 | sonnet | 外部搜索研究，sonnet 足够 |
| Challenger | opus | 反驳性验证需要更强推理能力 |
| Reporter | sonnet | 综合报告 + 文件 Edit，协调为主 |

## 前置依赖

无外部工具依赖。S3 研究员在有 WebSearch/Jina MCP 时效果更好，但不是必须条件。

## 权限设计

- **非元项目**（`.claude/user-level-write` 不存在）：审查仅针对项目级文件；用户级文件（`~/.claude/`）的发现写入 `~/.claude/proposals/`，不直接修改
- **元项目**（`.claude/user-level-write` 存在）：可直接修改 `~/.claude/` 下的 skill/agent 文件

## 自指模式

审查目标包含委员会自身文件（skill-review、skill-reviewer-s*、skill-researcher、skill-challenger、skill-reporter）时：
- Reporter 仅生成建议，**禁止直接 Edit**
- 不传入项目 CLAUDE.md（防止项目偏见影响通用工具审查）

## 用途

对已安装的 skill/agent 文件进行系统性质量评估，输出：
- Stage 1：四维并行发现（定义质量 / 链路审计 / 外部对标 / 可用性）
- Stage 2：Challenger 反驳验证 + Reporter 综合报告 + 直接修复
- 质量等级：🔴 不可用 / 🟡 可用有缺陷 / 🟢 生产可用 / ⭐ 优秀
