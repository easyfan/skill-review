#!/usr/bin/env bash
# check_size.sh — 检查目标文件行数是否超过阈值
# 用法：bash check_size.sh <REVIEWABILITY_THRESHOLD> <SHRINK_THRESHOLD> <SCRATCH_DIR> [file1 file2 ...]
# 退出码：0=全部通过或仅超 REVIEWABILITY（输出警告）；1=任意文件超 SHRINK（已输出错误）
set -euo pipefail

REVIEWABILITY_THRESHOLD="${1:?missing REVIEWABILITY_THRESHOLD}"
SHRINK_THRESHOLD="${2:?missing SHRINK_THRESHOLD}"
SCRATCH_DIR="${3:?missing SCRATCH_DIR}"
shift 3

oversized=0
for f in "$@"; do
  lines=$(wc -l < "$f")
  if [ "$lines" -gt "$SHRINK_THRESHOLD" ]; then
    echo "⛔ 文件过大，无法审查：$f（${lines} 行 > ${SHRINK_THRESHOLD} 行上限）"
    echo "原因：委员会成员上下文受限，裁定准确率显著下降。"
    echo "建议：先运行 /skill-shrink $(basename "$(dirname "$f")")，再重试。"
    echo "（scratch 锁已自动释放，无需手动清理）"
    rm -f "$SCRATCH_DIR/lock.pid"
    oversized=1
  elif [ "$lines" -gt "$REVIEWABILITY_THRESHOLD" ]; then
    echo "🟡 文件较大（${lines} 行），审查质量可能受影响，继续执行：$f"
  else
    echo "🟢 文件大小正常（${lines} 行）：$f"
  fi
done

exit "$oversized"
