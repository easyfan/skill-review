# skill-review 设计说明

本文档记录 skill-review 的设计决策、复杂度推导和参数来源。
不加入 YAML front-matter，不被 CC 自动加载到执行上下文。

---

## SCRATCH_DIR 路径设计

SCRATCH_DIR 使用固定路径（不含时间戳）：

```
$PROJECT_ROOT/.claude/agent_scratch/skill_review_committee/
```

**原因**：Reporter 会直接修改原始 skill/agent 文件，历史 findings 无需跨次保留；每次运行覆盖前次即可。

**对比 research-review**：research-review 的 Reporter 不修改源文件，需要保留多次审查的历史 findings 供比较，因此使用时间戳路径。

---

## 规模可审查性阈值推导

阈值计算公式：

```
n_max = sqrt(θ / (2βρ))
```

参数说明（CC + OpenRouter sonnet/opus 实测值，测量日期：~2026-Q1）：
- θ ≈ 43K：可用 token 上限（扣除系统 prompt 和工具预算后剩余）
- β ≈ 0.027：P0/P1 密度（条/行），基于 skill-review 自身和若干 agent 的实测值
- ρ ≈ 17：平均 token/行（CC skill 文件的典型密度）

代入得 n_max ≈ 220 行，设为 `REVIEWABILITY_THRESHOLD`。

**注意**：
- 阈值随 provider（直连 Anthropic 可能更高）和 skill 质量（β 值）变化
- 参数为近似估算，建议以实际超时为准
- β 和 ρ 基于小样本推导，具体 skill 的密度可能相差 2-3 倍

---

## 复杂度模型

review 工作量复杂度约为 **O(n^(α+1))**，其中：
- n = skill 行数
- α = P0/P1 密度指数（1≤α≤2），对同等质量水平的 skill，P0/P1 数 ∝ nᵅ
- 每次验证调用消耗 ∝ n tokens（需读取被审查文件）
- 总 context 增长 ∝ n^(α+1)

超过阈值的 skill 本身也往往过于单体化，拆分是有利于维护的正确工程决策。
协调者在展示工作量警告时无需向用户展示此推导，仅输出建议阈值（~220 行）即可。

---

## 格式快检设计

借鉴 skill-creator 的 `quick_validate.py` 思路，在委员会启动前前置过滤格式问题：
- 节省委员会算力：S1 可聚焦于更深层的设计质量问题，无需重复检查格式项
- Reporter 通过读取 `format_issues.md` 跟进格式发现，确保不丢失
- 格式问题标注 P3，不中断流程

---

## 自指模式设计

当审查目标包含委员会自身文件时进入自指模式，原因：

**避免自我参照悖论**：如果 Reporter 在审查 skill-review.md 时直接修改它，会改变正在执行的审查流程。

**两个关键约束**：
1. **禁止传入项目 CLAUDE.md**：这些 agent 是跨项目通用工具，用特定项目背景评审会引入偏见，导致在不同项目运行时产生矛盾的修改建议
2. **Reporter 禁止 Edit**：通过 prompt 层约束（非工具层硬约束）——CC 平台 Task 工具不支持通过调用参数覆盖子 Agent 的 allowed-tools，子 Agent 工具集由其自身 YAML front-matter 决定

---

## progress.md Schema 设计

使用结构化 schema，便于断点排查：

```
STAGE=N | DIM=<维度名> | STATUS=<SUCCESS/FAIL/STARTED> | FINDINGS=N | TIME=<ISO8601>
```

**设计意图**：
- 结构化格式使 `grep`/`awk` 可快速提取特定字段，无需解析 markdown
- Stage 1 各 Agent 完成后追加写入，不覆盖（append 语义）
- Stage 0 STARTED 提供会话 ID 和目标上下文，便于跨次对比

---

## 文件写入路径约定

| 文件 | 写入方 | 扩展名 | 备注 |
|------|--------|--------|------|
| lock.pid | 协调者 Bash 直写 | .pid | .pid 扩展名不被 *.md 清理影响 |
| s*_findings.md | Stage 1 Agent - Write 工具 | .md | 被 rm *.md 清理覆盖 |
| challenger_response.md | Challenger - Write 工具 | .md | 被 rm *.md 清理覆盖 |
| pipeline_status.md | 协调者 Bash 直写 | .md | 被 rm *.md 清理覆盖 |
| file_classification.md | classify_files.sh | .md | 被 rm *.md 清理覆盖 |
| progress.md | 协调者初始化 + Agent 追加 | .md | 被 rm *.md 清理覆盖 |

**关键约定**：lock.pid 使用 `.pid` 扩展名而非 `.md`，确保 `rm -f *.md` 不会误删锁文件。

---

## Proposal 机制

`~/.claude/proposals/` 存储 skill-review 在他指模式下发现的、针对目标文件的历史改进建议。

**自指模式下跳过 Proposal 扫描**：proposals/agents/ 和 proposals/commands/ 中可能存储关于 skill-review 自身的观察，注入会改变正在执行的审查流程，造成自我参照悖论。

---

## scripts/ 目录设计原则

每个脚本遵循以下约定：
- `#!/usr/bin/env bash` + `set -euo pipefail`（除需要手动控制 exit code 的脚本外）
- 通过位置参数传入所有输入，不读取环境变量（保证可独立测试）
- stdout = 结果数据；stderr = 错误/警告信息；exit code = 0/1 表示成功/失败
- 通过绝对路径调用：`bash "$SKILL_DIR/scripts/xxx.sh" arg1 arg2`

---

## Stage 1 执行约束速查

防止 context 饱和遗漏关键规则：

1. 4 个 Agent 必须**同一 turn 并发**调用，不得串行等待
2. Agent 全部返回后，检查 `sN_findings.md` 是否存在且非空；缺失或为空时**写占位文件**
3. 协调者读取完整 findings 通过 **Read tool**，不依赖 Agent 返回文本作为数据源

---

## Stage 1 Agent 职责表

| Agent | subagent_type | 职责 |
|-------|--------------|------|
| S1 | `skill-reviewer-s1` | 定义质量审计 |
| S2 | `skill-reviewer-s2` | 互动链路审计 |
| S3 | `skill-researcher` | 外部前沿研究（自带 WebSearch；注：非 `skill-reviewer-s3`） |
| S4 | `skill-reviewer-s4` | 可用性审计 |

---

## pipeline_status.md STATUS 枚举

| STATUS 值 | 触发场景 | Reporter 处理 |
|-----------|---------|--------------|
| `NORMAL` | Stage 2a Challenger 正常完成 | 使用 Challenger 裁定，按 CONFIRMED/DISPUTED 分层 |
| `ZERO_FINDINGS` | Stage 1 中场汇总零发现 | 跳过 Challenger 层，直接启动 Reporter 生成空报告 |
| `CHALLENGER_FAILED` | Challenger 崩溃，选 A 继续 | 无 Challenger 裁定，直接汇总 Stage 1 findings |

注：`PARTIAL_DIM` 是附加字段（非互斥 STATUS 值），与 `STATUS: NORMAL` 共存。Reporter 读取 pipeline_status.md 时，若存在 `PARTIAL_DIM:` 行，则按"含缺失维度的 NORMAL"模式处理：Challenger 对该维度仅输出 UNVERIFIABLE；Reporter 在报告中标注缺失维度。

---

## Stage 2a Challenger 策略选项

当 `EST_TOOL_CALLS > 25` 或 `TARGET_LINES > 400` 时展示：

- **A：精简模式** — 仅让 Challenger 处理 P0/P1 发现，跳过 P2/P3（节省约 40% 成本）
- **B：分批模式** — 按每批 5 个文件分多轮运行（适合 all 模式下文件数量多的场景）
- **C：跳过 Challenger** — 直接启动 Reporter，Challenger 裁定环节省略（最快，适合紧急场景）
- **D：终止** — 手动拆分目标后重新运行

---

## 成员说明

| 成员 | subagent_type | 模型 | 阶段 | 职责 |
|------|--------------|------|------|------|
| S1 定义质量审计员 | `skill-reviewer-s1` | sonnet | Stage 1 | prompt 清晰度、模型选型、工具集匹配、description 准确性 |
| S2 互动链路审计员 | `skill-reviewer-s2` | sonnet | Stage 1 | orchestration 模式、数据契约、并行/串行正确性、context rot 量化 |
| S3 外部前沿研究专员 | `skill-researcher` | sonnet + WebSearch | Stage 1 | 对标业界最佳实践，允许使用 WebSearch |
| S4 可用性审计员 | `skill-reviewer-s4` | sonnet | Stage 1 | 用户体验、输出格式、错误处理、进度反馈设计 |
| Challenger 挑战者 | `skill-challenger` | opus | Stage 2a | 对 Stage 1 发现做 CONFIRMED/DISPUTED/UNVERIFIABLE 裁定 |
| Reporter 汇总员 | `skill-reporter` | sonnet | Stage 2b | 生成报告，他指模式下直接修复目标文件，写入 Gotcha 数据库 |

注：S3 的 subagent_type 为 `skill-researcher`，非 `skill-reviewer-s3`（无该类型）。
