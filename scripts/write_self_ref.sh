#!/usr/bin/env bash
# write_self_ref.sh — 在自指模式下将 SELF_REF=true 写入 pipeline_status.md
# 用法：bash write_self_ref.sh <SELF_REF> <SCRATCH_DIR>
# 若 SELF_REF=true，追加标记到 pipeline_status.md 并输出确认
set -euo pipefail

SELF_REF="${1:?missing SELF_REF}"
SCRATCH_DIR="${2:?missing SCRATCH_DIR}"

if [ "$SELF_REF" = "true" ]; then
  printf "SELF_REF: true\n" >> "$SCRATCH_DIR/pipeline_status.md"
  echo "[自指模式] SELF_REF=true 已写入 pipeline_status.md（数据契约层约束）"
fi
