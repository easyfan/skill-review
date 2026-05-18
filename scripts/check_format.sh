#!/usr/bin/env bash
# check_format.sh — skill/agent 文件基础格式快检
# 用法：bash check_format.sh file1.md [file2.md ...]
# 退出码：0=全部通过, 1=有问题
# stdout：问题列表（空=无问题），写入文件时重定向即可
set -uo pipefail

if [ $# -eq 0 ]; then
  echo "用法：bash check_format.sh file1.md [file2.md ...]" >&2
  exit 1
fi

HAS_ISSUE=0

for f in "$@"; do
  IS_SKILL=false
  echo "$f" | grep -q "/skills/" && IS_SKILL=true

  FILE_ISSUES=()

  # 检查 1：YAML front-matter 是否存在
  if ! head -1 "$f" | grep -q "^---"; then
    FILE_ISSUES+=("❌ 缺少 YAML front-matter")
  fi

  # 检查 2：description 字段是否存在
  if ! grep -q "^description:" "$f"; then
    FILE_ISSUES+=("❌ 缺少 description 字段")
  else
    # 检查 3：description 长度 ≤ 1024 字符
    desc=$(grep "^description:" "$f" | head -1 | sed 's/^description:[[:space:]]*//')
    if [ ${#desc} -gt 1024 ]; then
      FILE_ISSUES+=("❌ description 超过 1024 字符（当前 ${#desc} 字符）")
    fi
  fi

  # 检查 4（仅 agents）：name 字段存在且为 kebab-case
  if echo "$f" | grep -q "/agents/"; then
    if ! grep -q "^name:" "$f"; then
      FILE_ISSUES+=("❌ agent 缺少 name 字段")
    else
      name=$(grep "^name:" "$f" | head -1 | sed 's/^name:[[:space:]]*//')
      if ! echo "$name" | grep -qE "^[a-z][a-z0-9-]*$"; then
        FILE_ISSUES+=("❌ name 不符合 kebab-case: $name")
      fi
    fi
  fi

  # 检查 5（仅 skills）：name 字段与父目录名一致
  if [ "$IS_SKILL" = "true" ]; then
    skill_dir=$(dirname "$f")
    expected_name=$(basename "$skill_dir")
    skill_name=$(grep "^name:" "$f" 2>/dev/null | head -1 | sed 's/^name:[[:space:]]*//')
    if [ -n "$skill_name" ] && [ "$skill_name" != "$expected_name" ]; then
      FILE_ISSUES+=("⚠️ skill name 字段（$skill_name）与目录名（$expected_name）不一致")
    fi
    # skills 不检查 model/tools 字段（这些字段在 SKILL.md 中不适用）
  fi

  # 检查 6（commands + agents，有 frontmatter 时）：formatter 字段存在且合法
  if head -1 "$f" | grep -q "^---" && ! echo "$f" | grep -q "/skills/"; then
    VALID_FORMATTERS="markdown|code|json|text"
    if ! grep -q "^formatter:" "$f"; then
      FILE_ISSUES+=("⚠️ 缺少 formatter 字段（合法值：markdown/code/json/text）")
    else
      fmt=$(grep "^formatter:" "$f" | head -1 | sed 's/^formatter:[[:space:]]*//')
      if ! echo "$fmt" | grep -qE "^($VALID_FORMATTERS)$"; then
        FILE_ISSUES+=("❌ formatter 值非法：$fmt（合法值：markdown/code/json/text）")
      fi
    fi
  fi

  if [ ${#FILE_ISSUES[@]} -gt 0 ]; then
    echo "=== $(basename "$f") ==="
    for issue in "${FILE_ISSUES[@]}"; do
      echo "  $issue"
    done
    echo ""
    HAS_ISSUE=1
  fi
done

exit $HAS_ISSUE
