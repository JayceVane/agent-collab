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
policy="$(ac_read_field approval_policy)"
pending="$(ac_pending_count)"

TOOL_NAME="${TOOL_NAME:-${1:-unknown}}"

case "$mode" in
  A)
    if [ "$phase" = "planning" ]; then
      echo "[agent-collab] 模式 A（先方案后代码）：当前处于规划阶段，写操作需先完成方案审批。"
      echo "[agent-collab] 工具: $TOOL_NAME  待审批: $pending"
      if [ "$policy" != "auto" ] && [ "$pending" -gt 0 ]; then
        echo "[agent-collab] 存在 $pending 项待审批，请使用 approve 放行后再执行写操作。"
        exit 2
      fi
    fi
    ;;
  B)
    :
    ;;
  C)
    echo "[agent-collab] 模式 C（全流程审批）：工具 $TOOL_NAME 需要审批确认。"
    if [ "$policy" = "manual" ]; then
      if [ "$pending" -eq 0 ]; then
        echo "[agent-collab] 策略为人工审批，已自动为此操作创建审批请求。"
        ac_add_approval "$TOOL_NAME 操作"
      fi
      echo "[agent-collab] 人工审批模式下存在未审批项，操作被阻断。"
      exit 2
    elif [ "$policy" = "hybrid" ] && [ "$pending" -gt 0 ]; then
      echo "[agent-collab] 混合策略下存在 $pending 项待审批，请先处理。"
      exit 2
    fi
    ;;
  *)
    echo "[agent-collab] 未知模式: $mode，跳过检查"
    ;;
esac

exit 0
