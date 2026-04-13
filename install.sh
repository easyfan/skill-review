#!/usr/bin/env bash
set -euo pipefail

# skill-review installer
# ✅ Verified by automated tests: this install path is covered by the skill-test pipeline (looper Stage 5).
#
# Usage:
#   bash install.sh [--target=<claude_home>]
#   bash install.sh --dry-run
#   bash install.sh --uninstall [--target=<claude_home>]
#   CLAUDE_DIR=<claude_home> bash install.sh      # packer convention (lower priority than --target)
#
# Installs:
#   commands/skill-review.md         → <claude_home>/commands/skill-review.md
#   agents/skill-reviewer-s1.md      → <claude_home>/agents/skill-reviewer-s1.md
#   agents/skill-reviewer-s2.md      → <claude_home>/agents/skill-reviewer-s2.md
#   agents/skill-researcher.md       → <claude_home>/agents/skill-researcher.md
#   agents/skill-reviewer-s4.md      → <claude_home>/agents/skill-reviewer-s4.md
#   agents/skill-challenger.md       → <claude_home>/agents/skill-challenger.md
#   agents/skill-reporter.md         → <claude_home>/agents/skill-reporter.md
#   skills/validate-plugin-manifest/ → <claude_home>/skills/validate-plugin-manifest/

TARGET="${CLAUDE_DIR:-${HOME}/.claude}"
DRY_RUN=false
UNINSTALL=false

# ── Resolve real script dir (symlink-safe) ────────────────────────────────────
SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  link_dir="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$link_dir/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --target=*)  TARGET="${arg#--target=}" ;;
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --help|-h)
      echo "Usage: bash install.sh [--target=<path>] [--dry-run] [--uninstall]"
      echo "  CLAUDE_DIR=<path> bash install.sh   # custom Claude config dir"
      exit 0 ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
skip() { printf "  \033[2m– %s (up to date)\033[0m\n" "$*"; }
warn() { printf "  \033[33m⚠\033[0m  %s\n" "$*"; }
info() { printf "  %s\n" "$*"; }
run()  { $DRY_RUN || "$@"; }

echo ""
echo "  skill-review — Claude Code plugin v$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/package.json'))['version'])" 2>/dev/null || echo '?')"
echo "  Target: $TARGET"
$DRY_RUN && echo "  Mode: DRY RUN (no files modified)"
echo ""

# ── Uninstall ──────────────────────────────────────────────────────────────
if $UNINSTALL; then
  echo "  Uninstalling..."

  for f in \
    "commands/skill-review.md" \
    "agents/skill-reviewer-s1.md" \
    "agents/skill-reviewer-s2.md" \
    "agents/skill-researcher.md" \
    "agents/skill-reviewer-s4.md" \
    "agents/skill-challenger.md" \
    "agents/skill-reporter.md"; do
    dst="$TARGET/$f"
    if [ -f "$dst" ]; then
      run rm "$dst"
      ok "Removed $dst"
    else
      skip "$(basename "$dst") (not found)"
    fi
  done

  skill_dst="$TARGET/skills/validate-plugin-manifest"
  if [ -d "$skill_dst" ]; then
    run rm -rf "$skill_dst"
    ok "Removed $skill_dst"
  else
    skip "skills/validate-plugin-manifest (not found)"
  fi

  echo ""
  echo "  Uninstall complete."
  echo ""
  exit 0
fi

# ── Install ────────────────────────────────────────────────────────────────
changed=0

run mkdir -p "${TARGET}/commands" "${TARGET}/agents" "${TARGET}/skills"

# Commands
src="$SCRIPT_DIR/commands/skill-review.md"
dst="$TARGET/commands/skill-review.md"
if [ -f "$dst" ] && diff -q "$src" "$dst" &>/dev/null; then
  skip "commands/skill-review.md"
else
  [ -f "$dst" ] && info "Updating  commands/skill-review.md..." || info "Installing commands/skill-review.md..."
  run cp "$src" "$dst"
  ok "commands/skill-review.md → $dst"
  changed=$((changed + 1))
fi

# Agents
for agent in skill-reviewer-s1 skill-reviewer-s2 skill-researcher skill-reviewer-s4 skill-challenger skill-reporter; do
  src="$SCRIPT_DIR/agents/${agent}.md"
  dst="$TARGET/agents/${agent}.md"
  if [ -f "$dst" ] && diff -q "$src" "$dst" &>/dev/null; then
    skip "agents/${agent}.md"
  else
    [ -f "$dst" ] && info "Updating  agents/${agent}.md..." || info "Installing agents/${agent}.md..."
    run cp "$src" "$dst"
    ok "agents/${agent}.md → $dst"
    changed=$((changed + 1))
  fi
done

# Skill: validate-plugin-manifest
skill_src="$SCRIPT_DIR/skills/validate-plugin-manifest"
skill_dst="$TARGET/skills/validate-plugin-manifest"
if [ -f "$skill_dst/SKILL.md" ] && diff -q "$skill_src/SKILL.md" "$skill_dst/SKILL.md" &>/dev/null; then
  skip "skills/validate-plugin-manifest"
else
  [ -d "$skill_dst" ] && info "Updating  skills/validate-plugin-manifest..." || info "Installing skills/validate-plugin-manifest..."
  run mkdir -p "$skill_dst"
  run cp -r "$skill_src/." "$skill_dst/"
  ok "skills/validate-plugin-manifest → $skill_dst"
  changed=$((changed + 1))
fi

# ── skill-shrink dependency check ──────────────────────────────────────────
echo ""
if [ -f "$TARGET/skills/skill-shrink/SKILL.md" ]; then
  ok "skill-shrink detected — files >400 lines will be auto-gated before review"
else
  warn "skill-shrink not installed"
  warn "skill-review will refuse to review files >400 lines without it."
  warn "Install skill-shrink: bash install.sh  (from easyfan/skill-shrinker)"
  warn "  or: /plugin marketplace add easyfan/skill-shrinker"
fi

# ── Footer ─────────────────────────────────────────────────────────────────
echo ""
if $DRY_RUN; then
  echo "  [dry-run] $changed file(s) would be modified."
else
  echo "  Done! $changed item(s) installed."
  echo ""
  echo "  Usage: /skill-review [target_list|all|all-commands|all-agents]"
  echo "  Example: /skill-review all"
fi
echo ""
