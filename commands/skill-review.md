---
name: skill-review
description: 对 Claude Code skill/agent/command 文件进行多维度委员会审查，生成分级报告并提供改进建议。当用户请求审查、评估或检查 skill/agent/command 文件质量时触发，包括但不限于："/skill-review"、"委员会审查"、"审查这个 skill/agent"、"review 一下"、"检查这个 skill/agent 写得怎么样"、"这个 skill 有什么问题"、"帮我看看这个 agent"、"agent 质量审查"。涉及多 subagent 并行和 opus Challenger，成本较高（视目标数量不同，约 $0.5-2+ USD），需用户指定目标文件
allowed-tools: ["Bash", "Read", "Write", "Agent"]
---
Follow the instructions in ~/.claude/skills/skill-review/SKILL.md with the arguments: $ARGUMENTS
