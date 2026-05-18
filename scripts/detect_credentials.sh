#!/usr/bin/env bash
# detect_credentials.sh — CLAUDE.md 敏感内容检测
# 用法：bash detect_credentials.sh "$CLAUDE_MD_PATH"
# 退出码：0=安全（无凭证）, 1=疑似含凭证
# 非交互环境（无 TTY）检测到凭证时直接 exit 1，不等待用户输入
set -uo pipefail

CLAUDE_MD="${1:?需要 CLAUDE.md 路径参数}"

if [ ! -f "$CLAUDE_MD" ]; then
  # 文件不存在：正常，无需检测
  exit 0
fi

# 检测常见凭证模式：api_key / token / secret / JWT / GitHub PAT 等
if grep -iEq '(api[_-]?key|access[_-]?token|secret[_-]?key|password|credential|private[_-]?key)\s*[:=]|(Bearer\s+[A-Za-z0-9]|ghp_|sk-|eyJ[A-Za-z0-9])' "$CLAUDE_MD"; then
  echo "⚠️ [安全提示] 检测到 CLAUDE.md 中可能包含凭证（api_key / token / secret / JWT / GitHub PAT 等）。" >&2
  echo "   若继续，CLAUDE.md 内容将包含在发送至 Anthropic API 的 prompt 中（Stage 1 共 4 次调用）。" >&2
  echo "   若 CLAUDE.md 含真实密钥，这些密钥将暴露在 API 请求中。" >&2
  echo "   非交互环境（CI/Agent 调用）下将自动中断。请清理 CLAUDE.md 中的敏感内容后重新运行。" >&2

  # 非交互环境（无 TTY）：直接中断（fail-safe）
  if [ ! -t 0 ]; then
    echo "已中断（非交互式环境，默认拒绝继续）。" >&2
    exit 1
  fi

  # 交互环境：等待用户明确确认
  echo "   请输入\"取消\"或其他非继续内容以中断；输入\"继续\"以明确接受此风险：" >&2
  read -r _confirm
  if ! echo "$_confirm" | grep -qi "继续\|continue\|yes\|y"; then
    echo "已中断。请清理 CLAUDE.md 中的敏感内容后重新运行。" >&2
    exit 1
  fi
fi

exit 0
