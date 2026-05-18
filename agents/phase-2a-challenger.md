---
name: phase-2a-challenger
description: skill-review Stage 2a：工作量度量 → Challenger 启动 → 失败路由。由 skill-review 协调者在 Stage 1 中场汇停后调用。
allowed-tools: ["Bash", "Read", "Write", "Agent"]
---
# Phase 2a：Challenger

由协调者传入：SKILL_DIR、SCRATCH_DIR、TARGET_FILES 数组、pipeline_status.md 路径。

## Step 2a-pre：工作量度量

```bash
eval "$(bash "$SKILL_DIR/scripts/compute_workload.sh" \
  "$SCRATCH_DIR" "${#TARGET_FILES[@]}" "${TARGET_FILES[@]}")"
# 输出 P0P1_COUNT EST_TOOL_CALLS TARGET_LINES
```

- `EST_TOOL_CALLS ≤ 25` 且 `TARGET_LINES ≤ 400`：标准模式，直接启动 Challenger
- 超标：向用户展示 A/B/C/D 策略并等待选择（策略说明见 DESIGN.md §Stage 2a Challenger 策略选项）

```bash
sed -i '' "s/^STATUS:.*/STATUS: NORMAL/" "$SCRATCH_DIR/pipeline_status.md"
```

## Step 2a：启动 Challenger

启动前输出：
```
[Stage 2a] 策略：<策略>（目标 <TARGET_LINES> 行，P0/P1 <P0P1_COUNT> 条）
预计等待：opus 约 3-10 分钟，超过 15 分钟可视为超时。请等待...
```

以 `subagent_type: "skill-challenger"`（opus）启动 Challenger Agent，传入：
- s1-s4_findings.md 路径列表
- 目标路径列表
- pipeline_status.md 路径
- 精简模式（策略 A）时：仅传 P0/P1 发现

## 超时与失败处理

超时（>15 分钟未返回）：输出 `⚠️ Challenger 超时，Stage 1 发现已保存在 $SCRATCH_DIR`，提供：
- A：跳过 Challenger 继续 Step 2b
- B：终止，保留 Stage 1 findings

Challenger 失败（challenger_response.md 未生成）：
- 选 A：
  ```bash
  sed -i '' "s/^STATUS:.*/STATUS: CHALLENGER_FAILED/" "$SCRATCH_DIR/pipeline_status.md"
  ```
  将 pipeline_status.md 显式传入 Reporter，继续 Step 2b
- 选 B：终止。如担心覆盖，先备份：
  `cp -r "$SCRATCH_DIR" /tmp/skill_review_backup_$(date +%s)`

## 预读 challenger_response.md（为 2b 准备）

Challenger 成功后，预读 challenger_response.md 并将内容传给协调者用于 2b：
- ≤200 行：全量读取
- >200 行：`grep -B3 -E "\[CONFIRMED\]|\[DISPUTED\]|\[UNVERIFIABLE\]"` 提取关键段；无匹配则回退全量前 200 行

将预读内容写入 `$SCRATCH_DIR/challenger_preview.md`，协调者在启动 2b 前 Read 此文件。
