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
TOOL_NAME="${TOOL_NAME:-${1:-unknown}}"

case "$mode" in
  C)
    ac_add_approval "$TOOL_NAME 写入完成，等待审查确认"
    echo "[agent-collab] 模式 C：已记录 $TOOL_NAME 操作，请审查后 approve/reject。"
    ;;
  A)
    if [ "$phase" = "executing" ]; then
      echo "[agent-collab] 模式 A 执行阶段：$TOOL_NAME 操作已记录。"
    fi
    ;;
esac

exit 0
