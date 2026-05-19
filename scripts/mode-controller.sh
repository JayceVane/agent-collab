#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# FIX #4: 统一为 .opencode/agent-collab-state.json（与插件 index.js 一致）
STATE_FILE=".opencode/agent-collab-state.json"

source "$SCRIPT_DIR/state-persistence.sh" "$STATE_FILE" >/dev/null 2>&1 || true

case "${1:-status}" in
  status)
    if [ -f "$STATE_FILE" ]; then
      mode="$(ac_read_field mode)"
      phase="$(ac_read_field phase)"
      policy="$(ac_read_field approval_policy)"
      pending="$(ac_pending_count)"
      echo "模式: ${mode:-?}  阶段: ${phase:-?}  策略: ${policy:-?}  待审批: ${pending}"
      if ac_git_available; then
        branch="$(ac_git_current_branch)"
        dirty="$(ac_git_dirty_count)"
        echo "Git: 已启用  分支: ${branch:-?}  脏工作区文件数: ${dirty}"
      else
        echo "Git: 当前目录不是 Git 仓库或 Git 不可用"
      fi
    else
      echo "[agent-collab] 状态未初始化，请先运行 init"
    fi
    ;;
  init)
    ac_init_state
    echo "已初始化协作状态"
    ;;
  mode)
    new_mode="${2:-}"
    case "$new_mode" in
      A|B|C) ;;
      *)
        echo "用法：$0 mode <A|B|C>"
        echo "  A = 先方案后代码"
        echo "  B = 直接实现后审查"
        echo "  C = 全流程分阶段审批"
        exit 1
        ;;
    esac
    ac_write_field mode "$new_mode"
    case "$new_mode" in
      A) ac_write_field phase "planning"   ;;
      B) ac_write_field phase "executing"  ;;
      C) ac_write_field phase "planning"   ;;
    esac
    echo "已切换到模式 $new_mode"
    ;;
  phase)
    new_phase="${2:-}"
    case "$new_phase" in
      planning|executing|reviewing|completed) ;;
      *)
        echo "用法：$0 phase <planning|executing|reviewing|completed>"
        exit 1
        ;;
    esac
    current_mode="$(ac_read_field mode)"
    case "$current_mode:$new_phase" in
      A:executing)
        pending="$(ac_pending_count)"
        if [ "$pending" -gt 0 ]; then
          echo "[agent-collab] 模式 A 下存在 ${pending} 项待审批，请先解决后再进入执行阶段"
          exit 1
        fi
        ;;
      C:*)
        pending="$(ac_pending_count)"
        if [ "$pending" -gt 0 ] && [ "$new_phase" != "planning" ]; then
          echo "[agent-collab] 模式 C 下存在 ${pending} 项待审批，请先解决后再切换阶段"
          exit 1
        fi
        ;;
    esac
    ac_write_field phase "$new_phase"
    echo "已切换到阶段 $new_phase"
    ;;
  policy)
    new_policy="${2:-}"
    case "$new_policy" in
      auto|manual|hybrid) ;;
      *)
        echo "用法：$0 policy <auto|manual|hybrid>"
        exit 1
        ;;
    esac
    ac_write_field approval_policy "$new_policy"
    echo "审批策略已设为 $new_policy"
    ;;
  approve)
    ac_resolve_approval approved
    echo "已放行最早一条待审批项"
    ;;
  reject)
    ac_resolve_approval rejected
    echo "已驳回最早一条待审批项"
    ;;
  request)
    desc="${2:-未指定操作}"
    ac_add_approval "$desc"
    echo "已添加审批请求: $desc"
    ;;
  validate)
    if ac_validate_state; then
      echo "状态文件校验通过"
    else
      exit 1
    fi
    ;;
  git-check)
    if ac_git_available; then
      branch="$(ac_git_current_branch)"
      dirty="$(ac_git_dirty_count)"
      protected="false"
      if ac_git_is_protected_branch; then
        protected="true"
      fi
      echo "Git 检查结果"
      echo "- 分支: $branch"
      echo "- 脏工作区文件数: $dirty"
      echo "- 是否受保护分支: $protected"
      echo "- 待审批项: $(ac_pending_count)"
    else
      echo "[agent-collab] 当前目录不是 Git 仓库或 Git 不可用"
      exit 1
    fi
    ;;
  *)
    echo "用法：$0 [status|init|mode <A|B|C>|phase <planning|executing|reviewing|completed>|policy <auto|manual|hybrid>|approve|reject|request <描述>|validate|git-check]"
    exit 1
    ;;
esac
