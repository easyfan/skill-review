---
name: skill-review
description: 对 Claude Code skill/agent/command 文件进行多维度委员会审查，生成分级报告并提供改进建议。当用户请求审查、评估或检查 skill/agent/command 文件质量时触发，包括但不限于："/skill-review"、"委员会审查"、"审查这个 skill/agent"、"review 一下"、"检查这个 skill/agent 写得怎么样"、"这个 skill 有什么问题"、"帮我看看这个 agent"、"agent 质量审查"。涉及多 subagent 并行和 opus Challenger，成本较高（视目标数量不同，约 $0.5-2+ USD），需用户指定目标文件
allowed-tools: ["Bash", "Read", "Write", "Agent"]
---
# Skills/Agents 设计委员会（SKILL 版）

**注意**：此为 `~/.claude/skills/skill-review/` 版本，与 `~/.claude/commands/skill-review.md` 逻辑等价，
bash 逻辑提取到 `scripts/`，设计说明移至 `DESIGN.md`。

## 用法
`/skill-review [target_list|all|all-commands|all-agents|all-skills]`

示例：
```
/skill-review skill-a               # 单个 skill（使用 skill name，非文件名）
/skill-review skill-a,skill-b       # 多个（逗号分隔，可含空格，自动修正）
/skill-review all-skills            # 全部 skills 目录下的文件
/skill-review all                   # commands + agents + skills 全量审查
```

---

## Step 0：初始化

```bash
SKILL_DIR="$HOME/.claude/skills/skill-review"
PROJECT_ROOT=$(pwd)
SCRATCH_DIR="$HOME/.claude/agent_scratch/skill_review_committee"
REPORT_DIR="$PROJECT_ROOT/.claude/reports"
```

**Step 0a：参数解析与目标发现**

- 空值检查（Step 0a-1）：`$ARGUMENTS` 为空时输出用法并退出
- 安全过滤（Step 0a-2）：白名单正则 `^(all|all-commands|all-agents|all-skills|[a-z][a-z0-9_-]+(,[a-z][a-z0-9_-]+)*)$`，不合法则退出
- 格式修正（Step 0a-3）：逗号+空格自动修正，无需确认

动态发现 skill 文件，构建"名称 → 绝对路径"映射表：

```bash
ls "$PROJECT_ROOT/.claude/commands/"*.md 2>/dev/null
ls "$PROJECT_ROOT/.claude/agents/"*.md 2>/dev/null
ls "$HOME/.claude/commands/"*.md 2>/dev/null
ls "$HOME/.claude/agents/"*.md 2>/dev/null
for skill_dir in "$HOME/.claude/skills"/*/; do
  [ -f "${skill_dir}SKILL.md" ] && echo "${skill_dir}SKILL.md"
done
```

自指模式检测（委员会成员文件名或路径匹配以下任一）：
- 文件名：`skill-reviewer-s1.md`, `skill-reviewer-s2.md`, `skill-reviewer-s4.md`, `skill-researcher.md`, `skill-challenger.md`, `skill-reporter.md`, `skill-review.md`
- 路径：target 文件位于 `~/.claude/skills/skill-review/` 目录下（如 `SKILL.md`）

检测到自指时，立即向用户输出：`[自指模式] 本次审查目标为委员会自身组件，Reporter 将仅生成建议，不执行文件修改。`

Reporter 仅生成建议不直接修改，**不传入项目 CLAUDE.md**。

**Step 0b：scratch 初始化**

```bash
bash "$SKILL_DIR/scripts/init_scratch.sh" "$SCRATCH_DIR" "$REPORT_DIR"
# 退出码 1 = 并发冲突，直接终止；退出码 0 = 成功继续

# 注册 trap，确保所有退出路径（凭证检测失败、用户中场选择"停止"等）都能释放锁
trap 'rm -f "$SCRATCH_DIR/lock.pid"' EXIT
```

写入初始 progress.md：`STAGE=0 | DIM=init | STATUS=STARTED | TIME=<datetime>`

**Step 0c：验证目标文件存在**

对每个目标文件检查是否存在，缺失时询问继续/终止。验证后更新最终目标列表 `TARGET_FILES[]`。
若排除后目标为空，立即终止。

**Step 0c-1：规模预检**

```bash
REVIEWABILITY_THRESHOLD=220  # ≤220 行全自动，221-400 行提示质量风险（基于实测审查质量曲线）
SHRINK_THRESHOLD=400          # >400 行强制退出，委员会成员上下文受限导致遗漏率显著上升
```

逐个检查每个目标文件的行数（多文件时每个单独检查，不用合计）：

```bash
for f in "${TARGET_FILES[@]}"; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$SHRINK_THRESHOLD" ]; then
    echo "⛔ 文件过大，无法审查：$f（${lines} 行 > ${SHRINK_THRESHOLD} 行上限）"
  fi
done
```

若任意目标文件超过 400 行，**立即强制退出**，输出以下信息后终止（先释放锁）：

```
⛔ skill-review 拒绝审查：<文件路径>（<N> 行）

文件超过 400 行上限，委员会审查质量将严重下降：
  • 委员会成员上下文受限，易遗漏深层问题
  • Challenger 裁定准确率下降
  • 报告可操作性降低

请先使用 skill-shrink 压缩至 ≤220 行，再重新触发审查：
  /skill-shrink <文件路径>
  或直接说："帮我 shrink 一下 <skill名>"

压缩完成后重新运行：/skill-review <目标>
```

```bash
rm -f "$SCRATCH_DIR/lock.pid"
# 退出，不继续后续流程
```

单文件在合理范围内继续：
- ≤220 行：🟢 全自动继续
- 221–400 行：🟡 提示审查质量可能受影响，继续执行

若目标文件数 > 15，输出 `all` 模式成本警告并询问继续/拆分。

**Step 0d：权限检测与文件分类**

```bash
eval "$(bash "$SKILL_DIR/scripts/classify_files.sh" \
  "$PROJECT_ROOT" "$SCRATCH_DIR" "${CLAUDE_CWD:-$HOME}" \
  "${TARGET_FILES[@]}")"
# 输出 ELEVATED=true/false（写入 file_classification.md）
```

**Step 0e：格式快检**

```bash
format_output=$(bash "$SKILL_DIR/scripts/check_format.sh" "${TARGET_FILES[@]}" 2>/dev/null || true)
echo "$format_output" > "$SCRATCH_DIR/format_issues.md"
```

格式问题不中断流程，Reporter 将从 `format_issues.md` 读取，标注 P3。

**Step 0e.5：CLAUDE.md 凭证检测**（仅他指模式）

```bash
[ "$SELF_REF" != "true" ] && bash "$SKILL_DIR/scripts/detect_credentials.sh" "$PROJECT_ROOT/CLAUDE.md"
# 退出码 1 时终止
```

**Step 0f：预读所有目标文件 YAML front-matter**

```bash
for f in "${TARGET_FILES[@]}"; do
  echo "=== $f ==="
  awk '/^---/{c++; if(c==2){print; exit}} {print}' "$f"
  echo ""
done
```

将完整输出作为**预读内容块**嵌入 Stage 1 Agent prompt（无需 Agent 重复 Read 文件头）。

**Step 0g：扫描 Pending Proposals**（仅他指模式）

在 `~/.claude/proposals/` 下查找目标文件名对应的 pending proposals（排除 status: ✅/applied/rejected），构建 Proposal 上下文块。

---

## Stage 1：并行专项审查

启动前输出：
```
---
[Stage 1] 并行启动 4 个审计 Agent（S1/S2/S3/S4）
  sonnet 模型预计 2-5 分钟；超过 10 分钟可视为超时
  （可检查 $SCRATCH_DIR 下是否有部分 findings 文件生成）
---
请等待...
```

**以下 4 次 Agent 调用必须在协调者的同一响应 turn 内，以单条消息多 tool call 形式（即 function_calls 数组包含全部 4 个 Agent tool 调用）并发发出，不得等待任意一个返回后才发出下一个。在同一 turn 内并发调用 Agent tool 4 次，分别启动 S1-S4：**

| Agent | subagent_type | 职责 |
|-------|--------------|------|
| S1 | `skill-reviewer-s1` | 定义质量审计 |
| S2 | `skill-reviewer-s2` | 互动链路审计 |
| S3 | `skill-researcher` | 外部前沿研究（S3 subagent 自带 WebSearch 权限；注：subagent_type 为 `skill-researcher`，非 `skill-reviewer-s3`） |
| S4 | `skill-reviewer-s4` | 可用性审计 |

每个 Agent 传入：目标路径列表、SCRATCH_DIR、YAML 预读块、findings 格式要求（`### [P0/P1/P2/P3]` 开头）、项目背景（自指模式用通用描述）、Proposal 上下文块。

等待完成，验证 `s{1,2,3,4}_findings.md` 非空，更新 progress.md。

协调者在 4 个 Agent 调用均返回后（Agent tool 调用为阻塞式，全部完成后继续），检查各 `sN_findings.md` 是否存在且非空；若某个文件缺失或为空，协调者直接写入占位文件（Write tool）：

```
# S{N} Findings
（Agent 未返回，该维度已跳过）
```

注：Agent tool 超时由 Claude Code 平台层处理，协调者无需额外超时逻辑；若 Agent 因平台超时终止，findings 文件通常不会生成，此时占位写入逻辑被触发。

- 在中场汇总中以 ⚠️ 标注该维度缺失
- 继续执行，不终止流程

---

## Stage 1 中场汇总与暂停

读取 4 个 findings 文件，向用户输出汇总报告，使用以下模板：

```
## Stage 1 审计完成 — 中场汇总

审计员状态：S1 [OK] | S2 [OK] | S3 [OK] | S4 [OK]（超时用 [⚠️ 超时]）
目标文件：N 个
发现总数：P0×a / P1×b / P2×c / P3×d

### P0 发现（须修复）
- [文件名] 标题（来源：S?）

### P1 发现（建议修复）
- [文件名] 标题（来源：S?）

（P2/P3 合并一行：共 X 条，Stage 2 报告中列出）

---
输入 "继续" 进入 Stage 2（Challenger + Reporter），或 "停止" 退出。
```

**此为必要交互节点，不支持无人值守模式。**

零发现时：写 `STATUS: ZERO_FINDINGS` 到 pipeline_status.md，跳过 Challenger，直接启动 Reporter。

---

## Stage 2：Challenger + Reporter

### pipeline_status.md STATUS 枚举

| STATUS 值 | 触发场景 | Reporter 处理 |
|-----------|---------|--------------|
| `NORMAL` | Stage 2a Challenger 正常完成 | 使用 Challenger 裁定，按 CONFIRMED/DISPUTED 分层 |
| `ZERO_FINDINGS` | Stage 1 中场汇总零发现 | 跳过 Challenger 层，直接生成空报告 |
| `CHALLENGER_FAILED` | Challenger 崩溃，选 A 继续 | 无 Challenger 裁定，直接汇总 Stage 1 findings |

**Step 2a-pre：工作量度量**

```bash
eval "$(bash "$SKILL_DIR/scripts/compute_workload.sh" \
  "$SCRATCH_DIR" "${#TARGET_FILES[@]}" "${TARGET_FILES[@]}")"
# 输出 P0P1_COUNT EST_TOOL_CALLS TARGET_LINES
```

- `EST_TOOL_CALLS ≤ 25` 且 `TARGET_LINES ≤ 400`：标准模式，直接启动 Challenger
- 超标：展示以下 A/B/C/D 策略选择：
  - **A：精简模式** — 仅让 Challenger 处理 P0/P1 发现，跳过 P2/P3（节省约 40% 成本）
  - **B：分批模式** — 按每批 5 个文件分多轮运行（适合 all 模式下文件数量多的场景）
  - **C：跳过 Challenger** — 直接启动 Reporter，Challenger 裁定环节省略（最快，适合紧急场景）
  - **D：终止** — 手动拆分目标后重新运行

```bash
printf "STATUS: NORMAL\n" > "$SCRATCH_DIR/pipeline_status.md"
```

**Step 2a：Challenger**（`subagent_type: "skill-challenger"`，opus）

启动前输出：
```
[Stage 2a] 策略：<策略>（目标 <TARGET_LINES> 行，P0/P1 <P0P1_COUNT> 条）
预计等待：opus 约 3-10 分钟，超过 15 分钟可视为超时。请等待...
```

Challenger 失败时（challenger_response.md 未生成）：
- 选 A：写 `STATUS: CHALLENGER_FAILED`，将 pipeline_status.md **显式传入** Reporter，继续 Step 2b
- 选 B：终止。⚠️ 注意：重新运行将清空此目录，如需保留 Stage 1 结果，先手动备份：
  `cp -r "$SCRATCH_DIR" /tmp/skill_review_backup_$(date +%s)`

**Step 2b：Reporter**（`subagent_type: "skill-reporter"`）

预读逻辑（两条路径，根据 pipeline_status.md 的 STATUS 分支）：

- **正常路径**（STATUS=NORMAL）：预读 `challenger_response.md`
  - ≤200 行：全量读取
  - >200 行：用 `grep -B3 -E "\[CONFIRMED\]|\[DISPUTED\]|\[UNVERIFIABLE\]"` 提取关键段；若 grep 无匹配，回退为全量读取前 200 行
  - 将预读内容内联到 Reporter prompt

- **Challenger 失败路径**（STATUS=CHALLENGER_FAILED）：跳过 `challenger_response.md` 预读步骤；Reporter 传参中省略该文件，将 `STATUS: CHALLENGER_FAILED` 字符串直接内联到 prompt

自指模式约束日志：
```bash
# 仅为审计日志，实际约束在 Reporter 传参 prompt 中实现，此行不提供约束能力
[ "$SELF_REF" = "true" ] && echo "[自指模式] Reporter 通过 prompt 约束禁止 Edit（prompt 层约束）"
```

Reporter 传参（正常路径 9 项；CHALLENGER_FAILED 路径 8 项，省略 challenger_response.md）：s1-s4_findings.md、challenger_response.md（正常路径）、format_issues.md、
**pipeline_status.md**（含 STATUS 路由逻辑）、目标路径列表、当前日期、SCRATCH_DIR、REPORT_DIR、file_classification.md。

Reporter 输出下一步建议时，使用最多 5 条、按优先级排序的项目符号列表，每条附对应的 skill 命令（如 `/skill-review`、`/skill-shrink`）。

---

## Stage 3（条件触发）：断言设计

Reporter 完成后检查 modification_log.md 是否含 description 变更，有则自动触发断言设计（协调者内联执行，不启动 Task）。产物写入 `stage3_assertions.md`。

注：Stage 3 由协调者内联执行，需额外占用至少 3 次工具调用（Read×1 + Write×1 + buffer×1）。在 Stage 2b 结束时，协调者应确认剩余工具调用配额充足，不足时跳过 Stage 3 并在输出中注明。

---

## 最终输出 + 清理

输出质量等级（🔴/🟡/🟢/⭐）、报告路径、修改记录、下一步建议（路径展开为绝对路径）。

```bash
rm -f "$SCRATCH_DIR/lock.pid"
```

---

## 委员会成员一览

| 成员 | 模型 | 阶段 |
|------|------|------|
| S1 定义质量审计员 | sonnet | Stage 1 |
| S2 互动链路审计员 | sonnet | Stage 1 |
| S3 外部前沿研究专员 | sonnet + WebSearch | Stage 1 |
| S4 可用性审计员 | sonnet | Stage 1 |
| Challenger 挑战者 | opus | Stage 2a |
| Reporter 汇总员+修改者 | sonnet + Edit | Stage 2b |
