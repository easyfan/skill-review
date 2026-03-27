#!/usr/bin/env bash
set -euo pipefail

# skill-review installer
#
# Usage:
#   bash install.sh [--target <claude_home>]
#   CLAUDE_DIR=<claude_home> bash install.sh      # packer 约定（优先级低于 --target）
#
# 安装内容：
#   commands/skill-review.md  → <claude_home>/commands/skill-review.md
#   agents/skill-reviewer-s1.md → <claude_home>/agents/skill-reviewer-s1.md
#   agents/skill-reviewer-s2.md → <claude_home>/agents/skill-reviewer-s2.md
#   agents/skill-researcher.md  → <claude_home>/agents/skill-researcher.md
#   agents/skill-reviewer-s4.md → <claude_home>/agents/skill-reviewer-s4.md
#   agents/skill-challenger.md  → <claude_home>/agents/skill-challenger.md
#   agents/skill-reporter.md    → <claude_home>/agents/skill-reporter.md

TARGET="${CLAUDE_DIR:-${HOME}/.claude}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${TARGET}/commands" "${TARGET}/agents"

# Install command
cp "${SCRIPT_DIR}/commands/skill-review.md" "${TARGET}/commands/skill-review.md"
echo "✅ commands/skill-review.md → ${TARGET}/commands/skill-review.md"

# Install agents
for agent in skill-reviewer-s1 skill-reviewer-s2 skill-researcher skill-reviewer-s4 skill-challenger skill-reporter; do
  cp "${SCRIPT_DIR}/agents/${agent}.md" "${TARGET}/agents/${agent}.md"
  echo "✅ agents/${agent}.md → ${TARGET}/agents/${agent}.md"
done

echo ""
echo "  skill-review installed → ${TARGET}"
echo "  Usage: /skill-review [target_list|all|all-commands|all-agents]"
echo "  Example: /skill-review all"
