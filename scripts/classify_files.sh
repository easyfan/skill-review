#!/usr/bin/env bash
# classify_files.sh — ELEVATED 检测 + USER/PROJECT 文件分类
# 用法：bash classify_files.sh "$PROJECT_ROOT" "$SCRATCH_DIR" "$CLAUDE_CWD" file1 [file2 ...]
# 退出码：0=成功
# stdout：ELEVATED=true 或 ELEVATED=false
# 副作用：写入 $SCRATCH_DIR/file_classification.md
set -uo pipefail

PROJECT_ROOT="${1:?需要 PROJECT_ROOT 参数}"
SCRATCH_DIR="${2:?需要 SCRATCH_DIR 参数}"
CLAUDE_CWD="${3:-$HOME}"
shift 3
TARGET_FILES=("$@")

# 检测 cc-config-manager 模式
# 从 PROJECT_ROOT 向上递归查找 .claude/user-level-write，止于 CLAUDE_CWD
ELEVATED=false
_search_dir="$PROJECT_ROOT"
while true; do
  if [ -f "$_search_dir/.claude/user-level-write" ]; then
    ELEVATED=true
    ELEVATED_DIR="$_search_dir"
    break
  fi
  # 到达上界（CLAUDE_CWD）后停止
  [ "$_search_dir" = "$CLAUDE_CWD" ] && break
  # 防止越过根目录
  [ "$_search_dir" = "/" ] && break
  _search_dir="$(dirname "$_search_dir")"
done
unset _search_dir

# 分类目标文件
USER_LEVEL_FILES=()
PROJECT_LEVEL_FILES=()
for f in "${TARGET_FILES[@]}"; do
  if [[ "$f" == "$HOME/.claude/"* ]]; then
    USER_LEVEL_FILES+=("$f")
  else
    PROJECT_LEVEL_FILES+=("$f")
  fi
done

# 写入分类结果（供 Reporter 读取，避免依赖 prompt 内联展开）
{
  echo "ELEVATED=$ELEVATED"
  echo "USER_LEVEL_FILES:"
  if [ ${#USER_LEVEL_FILES[@]} -gt 0 ]; then
    printf '%s\n' "${USER_LEVEL_FILES[@]}" | sed 's/^/- /'
  fi
  echo "PROJECT_LEVEL_FILES:"
  if [ ${#PROJECT_LEVEL_FILES[@]} -gt 0 ]; then
    printf '%s\n' "${PROJECT_LEVEL_FILES[@]}" | sed 's/^/- /'
  fi
} > "$SCRATCH_DIR/file_classification.md"

# 输出 ELEVATED 状态（供协调者读取）
echo "ELEVATED=$ELEVATED"
if [ "$ELEVATED" = "true" ]; then
  echo "ELEVATED_DIR=${ELEVATED_DIR:-$PROJECT_ROOT}"
fi
