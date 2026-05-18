#!/usr/bin/env bash
# read_frontmatter.sh — 预读所有目标文件的 YAML front-matter
# 用法：bash read_frontmatter.sh [file1 file2 ...]
# 输出：每个文件的 "=== <path> ===" + front-matter 内容（到第二个 ---）
set -euo pipefail

for f in "$@"; do
  echo "=== $f ==="
  awk '/^---/{c++; if(c==2){print; exit}} {print}' "$f"
  echo ""
done
