#!/usr/bin/env bash
# discover_targets.sh — 目标发现：支持命名空间 skill（po:release / dev-workflow）
# 用法：bash discover_targets.sh <MODE_OR_TARGETS> <PROJECT_ROOT> <HOME_DIR>
#   MODE_OR_TARGETS: all | all-commands | all-agents | all-skills | 逗号分隔 token 列表
# stdout：每行一个解析出的绝对路径（已去重，保序）
# stderr：UNRESOLVED: <token>（每个未解析 token 一行）
# exit：恒为 0（未解析项交由 SKILL.md Step 0c 处理）
#
# 解析策略（两者结合）：先查 name 字段索引，未命中再回退冒号→路径约定映射。
set -uo pipefail

TARGETS="${1:?需要 MODE_OR_TARGETS 参数}"
PROJECT_ROOT="${2:?需要 PROJECT_ROOT 参数}"
HOME_DIR="${3:-$HOME}"

# 搜索根（与原 SKILL.md Step 0a 一致）
CMD_ROOTS=("$PROJECT_ROOT/.claude/commands" "$HOME_DIR/.claude/commands")
AGENT_ROOTS=("$PROJECT_ROOT/.claude/agents" "$HOME_DIR/.claude/agents")
SKILLS_ROOT="$HOME_DIR/.claude/skills"
ALL_ROOTS=("${CMD_ROOTS[@]}" "${AGENT_ROOTS[@]}" "$SKILLS_ROOT")

# ── 可审查 skill 判定 ───────────────────────────────────────────────
# 必须有 frontmatter + description 字段；排除 rules/references 目录与文档/schema 文件
is_skill_file() {
  local f="$1"
  [ -f "$f" ] || return 1
  case "$f" in
    */rules/*|*/references/*) return 1 ;;
  esac
  local base; base="$(basename "$f")"
  case "$base" in
    DESIGN.md|README.md|*-schema.json|*.schema.json) return 1 ;;
  esac
  # frontmatter 第一行须为 ---，且 frontmatter 区间内含 description:
  head -1 "$f" | grep -q '^---[[:space:]]*$' || return 1
  awk '/^---[[:space:]]*$/{c++; next} c==1 && /^description:/{found=1} c>=2{exit} END{exit !found}' "$f"
}

# 提取 frontmatter 内的 name: 值（无则空）
extract_name() {
  awk '/^---[[:space:]]*$/{c++; next} c==1 && /^name:[[:space:]]/{sub(/^name:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit} c>=2{exit}' "$1"
}

# 标识符 → 路径 索引（用 \n 分隔的 "key\tpath" 行存储，避免 bash assoc array 兼容问题）
INDEX=""
index_put() {
  # 仅在 key 尚未存在时写入（首个搜索根优先：PROJECT 优先于 HOME）
  printf '%s' "$INDEX" | grep -q "^$1"$'\t' && return 0
  INDEX="${INDEX}$1"$'\t'"$2"$'\n'
}
index_get() {
  printf '%s' "$INDEX" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'
}

# 枚举一个 commands/agents 根下递归的所有 skill 文件
enum_root() {
  local root="$1"
  [ -d "$root" ] || return 0
  find "$root" -type f -name '*.md' 2>/dev/null | sort
}

# ── 构建 name 索引 ──────────────────────────────────────────────────
build_index() {
  local f name key
  # commands / agents 递归
  for root in "${CMD_ROOTS[@]}" "${AGENT_ROOTS[@]}"; do
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      is_skill_file "$f" || continue
      name="$(extract_name "$f")"
      if [ -n "$name" ]; then
        key="$name"
      else
        # name 缺失：命名空间 SKILL.md 用目录名，普通文件用 basename 去扩展名
        if [ "$(basename "$f")" = "SKILL.md" ]; then
          key="$(basename "$(dirname "$f")")"
        else
          key="$(basename "$f" .md)"
        fi
      fi
      index_put "$key" "$f"
    done < <(enum_root "$root")
  done
  # skills/*/SKILL.md
  if [ -d "$SKILLS_ROOT" ]; then
    for d in "$SKILLS_ROOT"/*/; do
      f="${d}SKILL.md"
      [ -f "$f" ] || continue
      is_skill_file "$f" || continue
      name="$(extract_name "$f")"
      [ -n "$name" ] || name="$(basename "$d")"
      index_put "$name" "$f"
    done
  fi
}

# ── 输出去重（保序）─────────────────────────────────────────────────
SEEN=""
emit() {
  local p="$1"
  printf '%s' "$SEEN" | grep -qxF "$p" && return 0
  SEEN="${SEEN}${p}"$'\n'
  printf '%s\n' "$p"
}

# 断言路径落在搜索根内（防越界）
in_roots() {
  local p="$1" r
  for r in "${ALL_ROOTS[@]}"; do
    case "$p" in "$r"/*) return 0 ;; esac
  done
  return 1
}

# ── all-* 模式枚举 ──────────────────────────────────────────────────
emit_all_commands() { for r in "${CMD_ROOTS[@]}"; do while IFS= read -r f; do [ -n "$f" ] && is_skill_file "$f" && emit "$f"; done < <(enum_root "$r"); done; }
emit_all_agents()   { for r in "${AGENT_ROOTS[@]}"; do while IFS= read -r f; do [ -n "$f" ] && is_skill_file "$f" && emit "$f"; done < <(enum_root "$r"); done; }
emit_all_skills()   { [ -d "$SKILLS_ROOT" ] && for d in "$SKILLS_ROOT"/*/; do f="${d}SKILL.md"; [ -f "$f" ] && is_skill_file "$f" && emit "$f"; done; }

# ── 显式 token 解析 ─────────────────────────────────────────────────
resolve_token() {
  local t="$1" hit cand
  # 1. name 索引精确命中
  hit="$(index_get "$t")"
  if [ -n "$hit" ] && in_roots "$hit"; then emit "$hit"; return 0; fi

  # 2. 含冒号 → 冒号转斜杠回退（po:release → commands/po/release.md）
  if [[ "$t" == *:* ]]; then
    local rel="${t//://}"
    for base in "${CMD_ROOTS[@]}" "${AGENT_ROOTS[@]}"; do
      cand="$base/$rel.md"
      if [ -f "$cand" ] && is_skill_file "$cand" && in_roots "$cand"; then emit "$cand"; return 0; fi
      cand="$base/$rel/SKILL.md"
      if [ -f "$cand" ] && is_skill_file "$cand" && in_roots "$cand"; then emit "$cand"; return 0; fi
    done
  else
    # 3. 无冒号 → 顶层文件 / 命名空间目录 SKILL.md / skills/<t>/SKILL.md
    for base in "${CMD_ROOTS[@]}" "${AGENT_ROOTS[@]}"; do
      cand="$base/$t.md"
      if [ -f "$cand" ] && is_skill_file "$cand" && in_roots "$cand"; then emit "$cand"; return 0; fi
      cand="$base/$t/SKILL.md"
      if [ -f "$cand" ] && is_skill_file "$cand" && in_roots "$cand"; then emit "$cand"; return 0; fi
    done
    cand="$SKILLS_ROOT/$t/SKILL.md"
    if [ -f "$cand" ] && is_skill_file "$cand" && in_roots "$cand"; then emit "$cand"; return 0; fi
  fi

  # 4. 全部未命中
  printf 'UNRESOLVED: %s\n' "$t" >&2
  return 1
}

# ── 主流程 ──────────────────────────────────────────────────────────
case "$TARGETS" in
  all)          build_index; emit_all_commands; emit_all_agents; emit_all_skills ;;
  all-commands) emit_all_commands ;;
  all-agents)   emit_all_agents ;;
  all-skills)   emit_all_skills ;;
  *)
    build_index
    # 逗号分隔；容错逗号+空格
    IFS=',' read -r -a _toks <<< "${TARGETS// /}"
    for t in "${_toks[@]}"; do
      [ -n "$t" ] || continue
      resolve_token "$t" || true
    done
    ;;
esac

exit 0
