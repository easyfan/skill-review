#!/usr/bin/env bash
# compute_workload.sh — Challenger 工作量度量
# 用法：bash compute_workload.sh "$SCRATCH_DIR" target_file_count [target_file1 ...]
# 退出码：0=成功
# stdout：三行，格式 KEY=VALUE（供调用方 eval 或解析）
#   P0P1_COUNT=N
#   EST_TOOL_CALLS=N
#   TARGET_LINES=N
set -uo pipefail

SCRATCH_DIR="${1:?需要 SCRATCH_DIR 参数}"
TARGET_FILE_COUNT="${2:?需要 target_file_count 参数}"
shift 2
TARGET_FILES=("$@")

# 目标文件总行数
if [ ${#TARGET_FILES[@]} -gt 0 ]; then
  TARGET_LINES=$(wc -l "${TARGET_FILES[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
else
  TARGET_LINES=0
fi

# P0/P1 发现总数（从 Stage 1 findings 文件统计）
P0P1_COUNT=$(grep -hc "^### \[P[01]\]" \
  "$SCRATCH_DIR"/s{1,2,3,4}_findings.md 2>/dev/null | \
  awk '{sum+=$1} END {print sum+0}')

# 预估工具调用数 = 4(findings Read) + target_files(Read) + P0P1×2(验证) + 2(Write报告)
EST_TOOL_CALLS=$((4 + TARGET_FILE_COUNT + P0P1_COUNT * 2 + 2))

echo "P0P1_COUNT=$P0P1_COUNT"
echo "EST_TOOL_CALLS=$EST_TOOL_CALLS"
echo "TARGET_LINES=$TARGET_LINES"
