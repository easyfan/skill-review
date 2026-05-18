#!/usr/bin/env bash
# init_scratch.sh — 初始化 skill-review scratch 目录（lockfile + 清理）
# 用法：bash init_scratch.sh "$SCRATCH_DIR" "$REPORT_DIR"
# 退出码：0=成功, 1=并发冲突（已有实例运行）
set -euo pipefail

SCRATCH_DIR="${1:?需要 SCRATCH_DIR 参数}"
REPORT_DIR="${2:?需要 REPORT_DIR 参数}"

mkdir -p "$SCRATCH_DIR"
mkdir -p "$REPORT_DIR"

# 并发 lockfile 检查：防止多实例同时运行覆盖 scratch 文件
# lock.pid 格式：<PID> <创建时间戳epoch>，用于检测 stale lock 和排除 PID 复用
if [ -f "$SCRATCH_DIR/lock.pid" ]; then
  read -r lock_pid lock_ts < "$SCRATCH_DIR/lock.pid"
  now_ts=$(date +%s)
  lock_age=$((now_ts - ${lock_ts:-0}))
  if [ "$lock_age" -gt 1800 ]; then
    # 锁龄超过 30 分钟，视为孤儿锁，自动清理后继续
    echo "⚠️ 检测到孤儿 lockfile（锁龄 ${lock_age}s），已自动清理。如有疑问，手动清理：rm $SCRATCH_DIR/lock.pid" >&2
    rm -f "$SCRATCH_DIR/lock.pid"
  elif kill -0 "$lock_pid" 2>/dev/null; then
    echo "错误：已有另一个 /skill-review 实例在运行（PID $lock_pid），请等待其完成后再执行。如误报，手动清理：rm $SCRATCH_DIR/lock.pid" >&2
    exit 1
  fi
fi

# 写入锁文件（.pid 扩展名，不受下方 *.md 清理影响）
echo "$$ $(date +%s)" > "$SCRATCH_DIR/lock.pid"

# 清理上次运行遗留的 scratch 文件
# MUST be after lock.pid write — 先写锁再清理，避免竞态中锁文件被误删
# 注：lock.pid 以 echo > 写入（协调者 bash 直写，.pid 后缀不受 *.md glob 影响）
#     s*_findings.md 等产物由 Agent Write 工具写入，两种路径各司其职
rm -f "$SCRATCH_DIR"/*.md

# 初始化完成断言
ls -d "$SCRATCH_DIR" > /dev/null || { echo "FATAL: SCRATCH_DIR 初始化失败，终止。" >&2; exit 1; }

echo "OK: scratch 目录已初始化 ($SCRATCH_DIR)"
