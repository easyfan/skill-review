#!/usr/bin/env bash
# load_gotchas.sh — Stage 0h: 加载 Gotcha 数据库，生成 gotcha_context.md
# 用法: bash load_gotchas.sh "$GOTCHA_DIR" "$GOTCHA_CONTEXT" "${TARGET_FILES[0]}"
# 退出码: 0 = 成功（含无 gotcha 情况）；1 = 参数错误

GOTCHA_DIR="$1"
GOTCHA_CONTEXT="$2"
FIRST_TARGET="$3"

if [ -z "$GOTCHA_DIR" ] || [ -z "$GOTCHA_CONTEXT" ] || [ -z "$FIRST_TARGET" ]; then
  echo "用法: load_gotchas.sh <GOTCHA_DIR> <GOTCHA_CONTEXT> <FIRST_TARGET_FILE>" >&2
  exit 1
fi

if [ ! -d "$GOTCHA_DIR" ]; then
  echo "ℹ️ $GOTCHA_DIR 不存在，跳过 gotcha 加载"
  echo "" > "$GOTCHA_CONTEXT"
  exit 0
fi

# 推断 skill 名：优先用 frontmatter name 字段（命名空间 skill 冒号 → 连字符，
# 与 gotcha 文件命名约定一致，如 name=po:release → 前缀 po-release）；
# 无 name 字段时回退到路径启发式。
SKILL_NAME=""
if [ -f "$FIRST_TARGET" ]; then
  SKILL_NAME=$(awk '/^---[[:space:]]*$/{c++; next} c==1 && /^name:[[:space:]]/{sub(/^name:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit} c>=2{exit}' "$FIRST_TARGET")
  SKILL_NAME="${SKILL_NAME//:/-}"
fi
if [ -z "$SKILL_NAME" ]; then
  # 回退：用父目录名；若目标直接在 commands/agents 下则用文件名
  SKILL_NAME=$(basename "$(dirname "$FIRST_TARGET")")
  if [ "$SKILL_NAME" = "commands" ] || [ "$SKILL_NAME" = "agents" ]; then
    SKILL_NAME=$(basename "$FIRST_TARGET" .md)
  fi
fi

# 加载精确匹配条目 + 通用条目
MATCHED=()
for f in "$GOTCHA_DIR/${SKILL_NAME}"-*.yaml "$GOTCHA_DIR"/universal-*.yaml; do
  [ -f "$f" ] && MATCHED+=("$f")
done

if [ ${#MATCHED[@]} -eq 0 ]; then
  echo "ℹ️ 无匹配 gotcha（skill=${SKILL_NAME}），Stage 1 全新审查"
  echo "" > "$GOTCHA_CONTEXT"
  exit 0
fi

{
  echo "# Gotcha 数据库（历史失效案例 + 已知高危模式）"
  echo "## 适用条目：${#MATCHED[@]} 条（skill=${SKILL_NAME} + universal）"
  echo ""
  echo "S1/S2 必须对每条 gotcha 执行 detection 检查，在 findings 中逐条标注「命中/未命中」。"
  echo "命中时 priority 不得低于 gotcha 记录值；未命中须明确写出，不得静默跳过。"
  echo ""
  for f in "${MATCHED[@]}"; do
    echo "---"
    cat "$f"
    echo ""
  done
} > "$GOTCHA_CONTEXT"

echo "✅ Gotcha 已加载：${#MATCHED[@]} 条 → $GOTCHA_CONTEXT"
