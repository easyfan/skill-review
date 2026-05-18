#!/usr/bin/env bash
# snapshot.sh — 快照机制：生成 diff 或建立基线，审查完成后更新快照
# 用法：bash snapshot.sh <SNAP_DIR> <SCRATCH_DIR> <TARGET_FILE...>
#
# 快照命名格式：<path-slug>_<basename>_<YYYYMMDD>.prev
#   path-slug = 文件路径最后两个目录层级，/ 替换为 _，避免同名文件碰撞
#   YYYYMMDD  = 审查日期，便于区分版本意图（"2026-04-30 审查前"）
#
# diff 文件命名：target_diff_<path-slug>_<basename>.md（无日期，每次覆盖）
set -euo pipefail

SNAP_DIR="$1"
SCRATCH_DIR="$2"
shift 2
TARGET_FILES=("$@")

mkdir -p "$SNAP_DIR"

TODAY="$(date '+%Y%m%d')"

for f in "${TARGET_FILES[@]}"; do
  BASENAME="$(basename "$f")"

  # 取路径最后两层作为 slug，去掉开头的 /，把 / 换成 _
  PARENT="$(dirname "$f")"
  GRANDPARENT="$(dirname "$PARENT")"
  P1="$(basename "$GRANDPARENT")"
  P2="$(basename "$PARENT")"
  PATH_SLUG="${P1}_${P2}"

  SNAP="$SNAP_DIR/${PATH_SLUG}_${BASENAME}_${TODAY}.prev"
  DIFF_OUT="$SCRATCH_DIR/target_diff_${PATH_SLUG}_${BASENAME}.md"

  # 查找同路径最新的历史快照（可能是昨天或更早）
  LATEST_SNAP="$(ls "$SNAP_DIR/${PATH_SLUG}_${BASENAME}_"*.prev 2>/dev/null | sort | tail -1 || true)"

  if [ -n "$LATEST_SNAP" ] && [ "$LATEST_SNAP" != "$SNAP" ]; then
    # 有历史快照（且不是今天的） → 生成 diff
    diff "$LATEST_SNAP" "$f" > "$DIFF_OUT" 2>/dev/null || true
    SNAP_DATE="$(basename "$LATEST_SNAP" .prev | grep -oE '[0-9]{8}$' || echo '未知日期')"
    echo "✅ 发现历史快照：${PATH_SLUG}/${BASENAME}（基线日期 ${SNAP_DATE}），diff 已生成，S1 将检查修改影响"
    # 建立今天的快照（保留历史，不覆盖旧版）
    cp "$f" "$SNAP"
  elif [ -n "$LATEST_SNAP" ] && [ "$LATEST_SNAP" = "$SNAP" ]; then
    # 今天已有快照（同一 session 第二次调用，审查结束时更新）
    diff "$LATEST_SNAP" "$f" > "$DIFF_OUT" 2>/dev/null || true
    cp "$f" "$SNAP"
    echo "✅ 已更新今日快照：${PATH_SLUG}/${BASENAME}_${TODAY}.prev"
  else
    # 首次审查 → 建立基线
    cp "$f" "$SNAP"
    echo "⚠️ 首次审查：已建立快照基线 ${PATH_SLUG}/${BASENAME}_${TODAY}.prev（本次无 diff，S1 执行全量静态审查）"
  fi
done
