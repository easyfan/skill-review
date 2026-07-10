---
name: phase-2b-reporter
description: skill-review Stage 2b：Reporter 传参组装 → Reporter Agent 启动 → Gotcha 写入协议 → Pattern 回流传参（他指模式）。由 skill-review 协调者在 Challenger 完成（或跳过）后调用。
allowed-tools: ["Bash", "Read", "Write", "Agent"]
---
# Phase 2b：Reporter

由协调者传入：SKILL_DIR、SCRATCH_DIR、TARGET_FILES、SELF_REF、REPORT_DIR、challenger_preview.md 内容（STATUS=NORMAL 时）。

## 自指标记写入

```bash
bash "$SKILL_DIR/scripts/write_self_ref.sh" "$SELF_REF" "$SCRATCH_DIR"
# prompt 层约束在 Reporter 传参 prompt 中额外声明（双重保险）
```

## 传参组装

读取 `pipeline_status.md` 的 STATUS 决定路径：

**正常路径**（STATUS=NORMAL）：传参 11 项：
s1-s4_findings.md、challenger_response.md、format_issues.md、pipeline_status.md、目标路径列表、当前日期、SCRATCH_DIR、REPORT_DIR、file_classification.md、proposal_context.md（他指模式）、generated_from.md（他指模式，内容内联）+ PROJECT_ROOT（他指模式，字符串传参，由协调者在 Step 2b 传入）

**CHALLENGER_FAILED 路径**：传参 10 项（省略 challenger_response.md），将 `STATUS: CHALLENGER_FAILED` 字符串内联到 prompt。

**自指模式**：不传入 proposal_context.md 和 generated_from.md，传参减少 2 项。

以 `subagent_type: "skill-reporter"` 启动 Reporter Agent。

Reporter 输出下一步建议时，使用最多 5 条、按优先级排序的项目符号列表，每条附对应的 skill 命令（如 `/skill-review`、`/skill-shrink`）。

## Reporter Gotcha 写入职责（仅他指模式）

每次 CONFIRMED P0/P1 修复后，Reporter 按以下 5 步完整协议执行（不得省略）：

1. **枚举待写条目**：遍历 modification_log.md 中所有 CONFIRMED P0/P1 修复，每条生成候选 gotcha（`pattern` 字段为机器可识别标识，如 `snapshot-mechanism-missing`）
2. **去重检查**：对每个候选，在 `$GOTCHA_DIR` 检查是否存在相同 `pattern` 字段的 `.yaml` 文件（`grep -rl "pattern: <value>" "$GOTCHA_DIR"`）
3. **写入新条目**（无重复时）：Write 新文件 `$GOTCHA_DIR/<skill>-<unix_ts_last4>.yaml`，必填字段：`pattern`、`title`、`priority`、`detection`（含 method 和 command）、`fix_template`、`regression_check`、`case_refs`
4. **更新已有条目**（有重复时）：在已有条目的 `case_refs` 末尾追加本次案例，更新 `last_seen` 为今日日期
5. **追加统计行**：在报告末尾追加：`📦 Gotcha 数据库：新增 N 条 / 更新 M 条 → ~/.claude/skill-gotchas/`

## Reporter Pattern 回流职责（仅他指模式）

`generated_from.md` 含有效条目（非"（无 generated-from 目标）"占位符）时，协调者须在 Reporter prompt 中内联 generated_from.md 内容与 PROJECT_ROOT；Reporter 在完成全部 CONFIRMED 修复后执行模板共性判定并生成 pattern 回写 proposal，完整协议见 skill-reporter agent Phase 3.5。无有效条目或自指模式时省略此传参，Reporter 跳过该阶段。
