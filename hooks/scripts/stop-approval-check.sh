#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_FILE=".claude/agent-collab.local.md"

source "$PLUGIN_ROOT/scripts/state-persistence.sh" "$STATE_FILE" >/dev/null 2>&1 || exit 0

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

enabled="$(ac_read_field enabled)"
if [ "$enabled" != "true" ]; then
  exit 0
fi

mode="$(ac_read_field mode)"
phase="$(ac_read_field phase)"
pending="$(ac_pending_count)"

if [ "$pending" -gt 0 ]; then
  case "$mode" in
    A)
      echo "[agent-collab] 模式 A 结束检查：存在 ${pending} 项未审批请求。"
      echo "[agent-collab] 当前阶段: $phase。请使用 approve/reject 处理后再结束。"
      exit 2
      ;;
    B)
      echo "[agent-collab] 模式 B 结束检查：存在 ${pending} 项待审批记录（仅提醒，不阻断）。"
      exit 0
      ;;
    C)
      echo "[agent-collab] 模式 C 结束检查：存在 ${pending} 项未审批请求。"
      echo "[agent-collab] 全流程审批模式下，所有审批项必须处理完毕才能结束。"
      exit 2
      ;;
  esac
fi

if [ "$phase" != "completed" ] && [ "$mode" = "C" ]; then
  echo "[agent-collab] 模式 C 结束检查：当前阶段为 $phase，未标记为 completed。"
  echo "[agent-collab] 请确认工作已完成后手动设置 phase 为 completed。"
  exit 2
fi

echo "[agent-collab] 结束检查通过。模式: $mode  阶段: $phase  待审批: $pending"
exit 0
