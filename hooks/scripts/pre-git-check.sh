#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_FILE=".claude/agent-collab.local.md"

source "$PLUGIN_ROOT/scripts/state-persistence.sh" "$STATE_FILE" >/dev/null 2>&1 || exit 0

HOOK_INPUT="$(cat || true)"
COMMAND_TEXT="$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
COMMAND_TEXT="${COMMAND_TEXT:-${TOOL_INPUT:-}}"

if [[ "$COMMAND_TEXT" != *git* ]]; then
  exit 0
fi

if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

enabled="$(ac_read_field enabled)"
if [ "$enabled" != "true" ]; then
  exit 0
fi

if ! ac_git_available; then
  echo "[agent-collab] 检测到 Git 命令，但当前目录不是 Git 仓库或 Git 不可用。"
  exit 2
fi

mode="$(ac_read_field mode)"
phase="$(ac_read_field phase)"
pending="$(ac_pending_count)"
branch="$(ac_git_current_branch)"
dirty="$(ac_git_dirty_count)"
protect_main="$(ac_read_field git_main_branch_protection)"
clean_checkout="$(ac_read_field git_require_clean_checkout)"
block_pending="$(ac_read_field git_block_on_pending_approvals)"
require_review="$(ac_read_field git_require_review_before_merge)"

is_high_risk=false
if [[ "$COMMAND_TEXT" =~ git[[:space:]]+(push|merge|rebase|reset|cherry-pick|checkout|switch|pull) ]] || [[ "$COMMAND_TEXT" =~ git[[:space:]]+commit ]]; then
  is_high_risk=true
fi

if [ "$protect_main" = "true" ] && ac_git_is_protected_branch; then
  if [[ "$COMMAND_TEXT" =~ git[[:space:]]+(commit|push|merge|rebase|reset|cherry-pick) ]]; then
    echo "[agent-collab] Git 保护：当前位于受保护分支 $branch，禁止直接执行高风险 Git 动作。"
    echo "[agent-collab] 请切换到任务分支后再继续。"
    exit 2
  fi
fi

if [ "$clean_checkout" = "true" ] && [ "$dirty" -gt 0 ]; then
  if [[ "$COMMAND_TEXT" =~ git[[:space:]]+(checkout|switch|merge|rebase|pull) ]]; then
    echo "[agent-collab] Git 检查：当前脏工作区文件数为 $dirty。"
    echo "[agent-collab] 在切换分支、合并、rebase 或 pull 前，请先整理未提交改动。"
    exit 2
  fi
fi

if [ "$block_pending" = "true" ] && [ "$pending" -gt 0 ] && [ "$is_high_risk" = true ]; then
  echo "[agent-collab] Git 检查：存在 $pending 项待审批，已阻断高风险 Git 动作。"
  echo "[agent-collab] 请先 approve/reject，再执行：$COMMAND_TEXT"
  exit 2
fi

if [ "$require_review" = "true" ]; then
  if [[ "$COMMAND_TEXT" =~ git[[:space:]]+(merge|push) ]] && [ "$mode" != "B" ]; then
    if [ "$phase" != "completed" ] && [ "$phase" != "reviewing" ]; then
      echo "[agent-collab] Git 检查：当前阶段为 $phase，尚未进入允许合并/推送的阶段。"
      echo "[agent-collab] 请先完成审查与放行流程。"
      exit 2
    fi
  fi
fi

exit 0
