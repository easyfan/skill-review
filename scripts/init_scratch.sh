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
# lock.pid 格式：<PID> <创建时间戳epoch>。PID 仅作诊断记录：写锁的 bash 为协调者
# 每次调用临时派生的短命进程，kill -0 存活检测恒失效（2026-07-08 审查发现），
# 故锁语义为纯时间戳——锁龄 ≤ LOCK_TTL 视为占用，正常流程结束时由协调者 rm 释放
LOCK_TTL=1800  # 秒；完整审查典型耗时 5-15 分钟，留足余量
if [ -f "$SCRATCH_DIR/lock.pid" ]; then
  read -r lock_pid lock_ts < "$SCRATCH_DIR/lock.pid" || true
  now_ts=$(date +%s)
  lock_age=$((now_ts - ${lock_ts:-0}))
  if [ "$lock_age" -gt "$LOCK_TTL" ]; then
    # 锁龄超过 TTL，视为孤儿锁，自动清理后继续
    echo "⚠️ 检测到孤儿 lockfile（锁龄 ${lock_age}s > ${LOCK_TTL}s），已自动清理。如有疑问，手动清理：rm $SCRATCH_DIR/lock.pid" >&2
    rm -f "$SCRATCH_DIR/lock.pid"
  else
    echo "错误：已有另一个 /skill-review 实例在运行（锁龄 ${lock_age}s，创建者 PID ${lock_pid:-未知}），请等待其完成后再执行。若确认无实例在运行（如上次异常中断），手动清理：rm $SCRATCH_DIR/lock.pid" >&2
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
