---
name: skill-review
description: 对 Claude Code skill/agent/command 文件进行多维度委员会审查，生成分级报告并提供改进建议。当用户请求审查、评估或检查 skill/agent/command 文件质量时触发，包括但不限于："/skill-review"、"委员会审查"、"审查这个 skill/agent"、"review 一下"、"检查这个 skill/agent 写得怎么样"、"这个 skill 有什么问题"、"帮我看看这个 agent"、"agent 质量审查"。涉及多 subagent 并行和 opus Challenger，成本较高（视目标数量不同，约 $0.5-2+ USD），需用户指定目标文件
allowed-tools: ["Bash", "Read", "Write", "Agent"]
---
# Skills/Agents 设计委员会

## 用法
`/skill-review [target_list|all|all-commands|all-agents|all-skills]`

示例：
```
/skill-review skill-a               # 单个 skill（使用 skill name，非文件名）
/skill-review skill-a,skill-b       # 多个（逗号分隔，可含空格，自动修正）
/skill-review all-skills            # 全部 skills 目录下的文件
/skill-review all-commands          # 全部 commands 目录下的文件
/skill-review all-agents            # 全部 agents 目录下的文件
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
- 安全过滤（Step 0a-2）：白名单正则 `^(all|all-commands|all-agents|all-skills|[a-z][a-z0-9_-]+(,[a-z][a-z0-9_-]+)*)$`，不合法则输出 `无效目标格式：'<输入值>'。合法格式：小写字母/数字/连字符，如 skill-review 或 skill-a,skill-b。附加说明请通过对话传入，不应附在参数中。` 后退出
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
# 退出码 1 = 并发冲突，直接终止（init_scratch.sh 已输出锁持有者 PID 和手动清除命令）；退出码 0 = 成功继续

# 注册 trap，确保所有退出路径（凭证检测失败、用户中场选择"停止"等）都能释放锁
trap 'rm -f "$SCRATCH_DIR/lock.pid"' EXIT

# P0-3：pipeline_status.md 覆盖初始化（防止多次追加产生多行 STATUS 冲突）
printf "STATUS: PENDING\n" > "$SCRATCH_DIR/pipeline_status.md"

# P0-1：清零旧批次 findings（防止 Challenger 读取跨批次累积内容）
rm -f "$SCRATCH_DIR"/{s1,s2,s3,s4}_findings.md "$SCRATCH_DIR/challenger_response.md"
```

写入初始 progress.md：`STAGE=0 | DIM=init | STATUS=STARTED | TIME=<datetime>`

**Step 0c：验证目标文件存在**

对每个目标文件检查是否存在，缺失时询问继续/终止。验证后更新最终目标列表 `TARGET_FILES[]`。
若排除后目标为空，立即终止。

**Step 0c-1：规模预检**（阈值推导见 DESIGN.md §规模可审查性阈值推导）

```bash
bash "$SKILL_DIR/scripts/check_size.sh" 220 400 "$SCRATCH_DIR" "${TARGET_FILES[@]}"
# exit 1 = 任意文件超 400 行（已输出原因+建议），直接终止；exit 0 = 继续
```

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
yaml_preview=$(bash "$SKILL_DIR/scripts/read_frontmatter.sh" "${TARGET_FILES[@]}")
```

将完整输出作为**预读内容块**嵌入 Stage 1 Agent prompt（无需 Agent 重复 Read 文件头）。

**Step 0g：扫描 Pending Proposals**（两种模式均执行；自指模式下 Reporter 仅列出建议，不直接修复）

扫描 `$HOME/.claude/proposals/` 和 `$PROJECT_ROOT/.claude/proposals/` 两个目录，查找与目标文件名相关的 pending proposals（排除含 `status:.*✅/applied/rejected` 的文件）。向用户输出 `[Step 0g] Proposals 扫描完成：发现 N 条 pending proposals` 或 `未发现待处理 proposals`，结果写入 `$SCRATCH_DIR/proposal_context.md`。

```bash
# 筛选逻辑：文件名或内容含 skill_name 且未被排除
# 格式：每条含文件名、路径、标题摘要
# 无 proposals 时写入：（无 pending proposals）
```

**Proposal 上下文块格式**（传入 Stage 1 Agent 时内联）：
```
## Pending Proposals
### <文件名>
- 路径: <绝对路径>
- 摘要: <标题行>
```
无 proposals 时传 `（无 pending proposals）` 占位符。

**Reporter 处理规则**：从 `proposal_context.md` 读取内容，在报告中新增"Proposals 摘要"节，注明"已覆盖 N 条 proposals"或"无 pending proposals"，findings 涉及 proposal 时在该节关联标注。

**Step 0h：快照机制**

```bash
bash "$SKILL_DIR/scripts/snapshot.sh" "$HOME/.claude/.skill-snapshots" "$SCRATCH_DIR" "${TARGET_FILES[@]}"
# 有 prev 快照则生成 target_diff_<filename>.md；无则建立基线
trap 'rm -f "$SCRATCH_DIR/lock.pid"; bash "$SKILL_DIR/scripts/snapshot.sh" "$HOME/.claude/.skill-snapshots" "$SCRATCH_DIR" "${TARGET_FILES[@]}"' EXIT
```

若存在 `target_diff_*.md`，S1 须执行 diff 检查清单（见 Stage 1 传参说明）。

**Step 0i：Gotcha 数据库加载**（仅他指模式）

```bash
bash "$SKILL_DIR/scripts/load_gotchas.sh" \
  "$HOME/.claude/skill-gotchas" \
  "$SCRATCH_DIR/gotcha_context.md" \
  "${TARGET_FILES[0]}"
# 加载逻辑：精确匹配当前 skill（<skill-name>-*.yaml）+ 通用模式（universal-*.yaml）
# 输出条数示例：已加载 3 条 gotcha（media-editorial×2 + universal×1），注入 S1/S2
```

`gotcha_context.md` 将作为**必读上下文**注入 S1、S2 的 prompt（S3/S4 不注入）。

---

# 执行约束见 DESIGN.md §Stage 1 执行约束速查

## Stage 1：并行专项审查

启动前输出（`$SCRATCH_DIR` 展开为实际路径，如 `~/.claude/agent_scratch/skill_review_committee`）：
```
---
[Stage 1] 批次 <N>/<TOTAL> — 目标：<target_file_names>
  并行启动 4 个审计 Agent（S1/S2/S3/S4）
  sonnet 模型预计 2-5 分钟；超过 10 分钟可视为超时
  超时时可检查中间结果：ls ~/.claude/agent_scratch/skill_review_committee/*_findings.md
---
请等待...
```

**以下 4 次 Agent 调用必须在协调者的同一响应 turn 内并发发出（单条消息，4 个 tool calls），不得串行等待。**（Agent 职责表见 DESIGN.md §Stage 1 Agent 职责表）

每个 Agent 传入：目标路径列表、SCRATCH_DIR 绝对路径、YAML 预读块、findings 格式要求（`### [P0/P1/P2/P3]` 开头）、项目背景（自指模式用通用描述）、Proposal 上下文块。

**构造每个 Agent prompt 时，必须将 `$SCRATCH_DIR` 展开为绝对路径后内联（不得写变量名），格式：`scratch 目录：<绝对路径> | findings 文件：<绝对路径>/sN_findings.md`，不得自行推断路径。**

**Agent 返回值约束（防止 coordinator context 膨胀）**：每个 Agent 的返回文本不超过 300 token（摘要格式：发现总数 + P0/P1 标题列表）。完整 findings 必须写入 SCRATCH_DIR 对应文件；协调者通过 Read tool 读取完整 findings，**不依赖 Agent 返回文本作为数据源**。

**S2 专属传参**（context rot 量化评估，仅对多阶段 skill，Phase 数 ≥ 2 或步骤数 ≥ 5 时强制传入）：
> 请额外构建"执行链体量估算表"：列出各关键阶段的预估 tool calls 数和后续依赖项。
> 风险等级判定：累计 ≤20 次 = 低，20-60 次 = 中（建议 manifest 物化），>60 次 = 高（必须给出拆分 Proposal）。
> 参照 `~/.claude/wiki/pages/ccm_skill-review-audit-2026-04.md` 反思 3.3 的表格模板（文件不存在时，使用内联默认列：`阶段 | 预估 tool calls | 后续依赖`）。

**Gotcha 注入规则**（差异化传参）：
- **S1、S2**：额外传入 `gotcha_context.md` 全文，并在 prompt 头部加入强制执行要求：
  > 以下为该 skill 的历史失效模式（Gotcha 数据库）。你必须：①对每条 gotcha 执行其 `detection` 描述的检查；②在 findings 末尾新增「Gotcha 核查」节，逐条列出「命中/未命中」及判定依据；③命中时该发现 priority 不得低于 gotcha 记录值。
- **S3、S4**：不注入 gotcha_context.md（gotcha 为内部执行历史，与外部研究和 UX 审查无关）。

等待完成，验证 `s{1,2,3,4}_findings.md` 非空，更新 progress.md。

协调者在 4 个 Agent 调用均返回后（Agent tool 调用为阻塞式，全部完成后继续），检查各 `sN_findings.md` 是否存在且非空；若某个文件缺失或为空，协调者直接写入占位文件（Write tool）：

```
# S{N} Findings
（Agent 未返回，该维度已跳过）
```

注：Agent tool 超时由 Claude Code 平台层处理，协调者无需额外超时逻辑；若 Agent 因平台超时终止，findings 文件通常不会生成，此时占位写入逻辑被触发。

- 在中场汇总中以 ⚠️ 标注该维度缺失，并说明影响（如"S2 互动链路审查缺失，orchestration 问题可能漏检，如需完整覆盖可重跑 `/skill-review <目标>`"）
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
输入"继续"（同义：continue/yes/好/ok）→ Stage 2；"停止"（同义：stop/no/退出/取消）→ 退出；其他输入默认停止（收到无法识别的输入时输出：「未识别输入，已停止流程。如需继续请重新运行。」）。
```

**此为必要交互节点，不支持无人值守模式。**

零发现时：执行 `sed -i "s/^STATUS:.*/STATUS: ZERO_FINDINGS/" "$SCRATCH_DIR/pipeline_status.md"`，跳过 Challenger，直接启动 Reporter。

---

## Stage 2：Challenger + Reporter

# STATUS 枚举见 DESIGN.md §pipeline_status.md STATUS 枚举

当任一 `sN_findings.md` 为占位文件（含"Agent 未返回，该维度已跳过"）时，协调者在写入占位文件后追加：
```bash
printf "\nPARTIAL_DIM: S%d\n" "$N" >> "$SCRATCH_DIR/pipeline_status.md"
```

**Step 2a**：以 `subagent_type: "general-purpose"` 启动 Phase 2a Agent，传入 `agents/phase-2a-challenger.md` 内容作为 prompt，附上 SKILL_DIR、SCRATCH_DIR、TARGET_FILES、pipeline_status.md 路径。等待完成后读取 `$SCRATCH_DIR/challenger_preview.md`。

**Step 2b**：以 `subagent_type: "general-purpose"` 启动 Phase 2b Agent，传入 `agents/phase-2b-reporter.md` 内容作为 prompt，附上 SKILL_DIR、SCRATCH_DIR、TARGET_FILES、SELF_REF、REPORT_DIR 及 challenger_preview.md 内容。

---

## Stage 3（条件触发）：断言设计

Reporter 完成后，**自指模式下跳过 Stage 3**（Reporter 未执行修改，modification_log.md 不含有效变更）：

```bash
if [ "$SELF_REF" = "true" ]; then
  echo "[自指模式] Stage 3 跳过，Reporter 未执行文件修改"
  # 跳过后续触发逻辑
  return 0 2>/dev/null || true
fi
```

非自指模式：检查 modification_log.md 是否含 description 变更，有则自动触发断言设计（协调者内联执行，不启动 Task）。产物写入 `stage3_assertions.md`。

注：Stage 3 由协调者内联执行，需额外占用至少 3 次工具调用（Read×1 + Write×1 + buffer×1）。在 Stage 2b 结束时，协调者应确认剩余工具调用配额充足，不足时跳过 Stage 3 并在输出中注明。

---

## 最终输出 + 清理

输出质量等级（🔴/🟡/🟢/⭐）、报告路径、修改记录、下一步建议（路径展开为绝对路径）。

```bash
rm -f "$SCRATCH_DIR/lock.pid"
```

# 委员会成员一览见 DESIGN.md §成员说明
