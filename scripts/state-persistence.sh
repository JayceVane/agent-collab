#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${1:-.claude/agent-collab.local.md}"

ac_has_field() {
  local field="$1"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  sed -n '/^---$/,/^---$/p' "$STATE_FILE" | grep -qE "^${field}:"
}

ac_insert_field() {
  local field="$1"
  local value="$2"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v field="$field" -v value="$value" '
    BEGIN { in_frontmatter=0; inserted=0 }
    /^---$/ {
      if (in_frontmatter==1 && !inserted) {
        print field ": " value
        inserted=1
      }
      in_frontmatter++
      print
      next
    }
    { print }
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

ac_upsert_field() {
  local field="$1"
  local value="$2"
  if ! ac_has_field "$field"; then
    ac_insert_field "$field" "$value"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  awk -v field="$field" -v value="$value" '
    BEGIN { in_frontmatter=0; changed=0 }
    /^---$/ { in_frontmatter++; print; next }
    in_frontmatter==1 && $0 ~ "^"field":" && !changed {
      print field ": " value
      changed=1
      next
    }
    { print }
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

ac_migrate_state() {
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi

  ac_upsert_field enabled true
  ac_upsert_field mode A

  local phase
  phase="$(ac_read_field phase)"
  case "$phase" in
    planning|executing|reviewing|completed) ;;
    *) ac_upsert_field phase planning ;;
  esac

  ac_upsert_field approval_policy hybrid
  ac_upsert_field pending_approvals "[]"
  ac_upsert_field completed_tasks "[]"
  ac_upsert_field active_agents "[]"
  ac_upsert_field git_main_branch_protection true
  ac_upsert_field git_require_clean_checkout true
  ac_upsert_field git_block_on_pending_approvals true
  ac_upsert_field git_require_review_before_merge true
}

# ── 初始化 ──────────────────────────────────────────────────────
ac_init_state() {
  if [ -f "$STATE_FILE" ]; then
    ac_migrate_state
    return 0
  fi
  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" <<'EOF'
---
enabled: true
mode: A
phase: planning
approval_policy: hybrid
pending_approvals: []
completed_tasks: []
active_agents: []
git_main_branch_protection: true
git_require_clean_checkout: true
git_block_on_pending_approvals: true
git_require_review_before_merge: true
---

# 协作状态

## 当前任务

- 待初始化

## 备注

- 该文件用于本地协作状态记录
- 建议加入版本控制忽略规则
EOF
}

# ── 读取字段 ────────────────────────────────────────────────────
# 从 YAML frontmatter 读取指定字段值
# 用法: ac_read_field <字段名>
ac_read_field() {
  local field="$1"
  if [ ! -f "$STATE_FILE" ]; then
    echo ""
    return 1
  fi
  # 提取 --- 之间的内容，找到目标字段
  sed -n '/^---$/,/^---$/p' "$STATE_FILE" \
    | grep -E "^${field}:" \
    | head -1 \
    | sed "s/^${field}: *//"
}

# ── 写入字段 ────────────────────────────────────────────────────
# 更新 frontmatter 中指定字段值（标量）
# 用法: ac_write_field <字段名> <新值>
ac_write_field() {
  local field="$1"
  local value="$2"
  if [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 错误：状态文件不存在，请先初始化" >&2
    return 1
  fi
  ac_upsert_field "$field" "$value"
}

# ── 追加审批项 ──────────────────────────────────────────────────
# 在 pending_approvals 数组中添加一条审批记录
# 用法: ac_add_approval <描述>
ac_add_approval() {
  local desc="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
  if [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 错误：状态文件不存在" >&2
    return 1
  fi
  local tmp_file
  tmp_file="$(mktemp)"
  # 在 frontmatter 的 pending_approvals: [] 或已有元素后追加
  awk -v desc="$desc" -v ts="$ts" '
    BEGIN { in_fm=0; done=0 }
    /^---$/ { in_fm++; next }
    in_fm==1 && /^pending_approvals: *\[\]/ && !done {
      print "pending_approvals:"
      print "  - desc: \"" desc "\""
      print "    status: pending"
      print "    ts: " ts
      done=1
      next
    }
    in_fm==1 && /^pending_approvals:$/ && !done {
      print $0
      print "  - desc: \"" desc "\""
      print "    status: pending"
      print "    ts: " ts
      done=1
      next
    }
    { print }
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

# ── 解决审批项 ──────────────────────────────────────────────────
# 将最早的 pending 审批项标记为 approved 或 rejected
# 用法: ac_resolve_approval <approved|rejected>
ac_resolve_approval() {
  local verdict="$1"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v verdict="$verdict" '
    BEGIN { in_fm=0; resolved=0 }
    /^---$/ { in_fm++; next }
    in_fm==1 && /status: pending/ && !resolved {
      sub(/status: pending/, "status: " verdict)
      resolved=1
    }
    { print }
  ' "$STATE_FILE" > "$tmp_file"
  mv "$tmp_file" "$STATE_FILE"
}

# ── 统计待审批数量 ──────────────────────────────────────────────
ac_pending_count() {
  if [ ! -f "$STATE_FILE" ]; then
    echo 0
    return
  fi
  local count
  count="$(grep -c 'status: pending' "$STATE_FILE" 2>/dev/null || echo 0)"
  echo "$count"
}

# ── Git 状态辅助 ────────────────────────────────────────────────
ac_git_available() {
  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

ac_git_current_branch() {
  if ! ac_git_available; then
    echo "N/A"
    return 1
  fi

  git branch --show-current 2>/dev/null || echo "DETACHED"
}

ac_git_dirty_count() {
  if ! ac_git_available; then
    echo 0
    return 0
  fi

  git status --porcelain 2>/dev/null | wc -l | tr -d ' '
}

ac_git_is_protected_branch() {
  local branch
  branch="$(ac_git_current_branch)"
  case "$branch" in
    main|master) return 0 ;;
    *) return 1 ;;
  esac
}

# ── 验证状态文件 ────────────────────────────────────────────────
# 检查必要字段是否存在且合法，返回 0=有效 1=无效
ac_validate_state() {
  if [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 状态文件不存在" >&2
    return 1
  fi
  local mode
  mode="$(ac_read_field mode)"
  case "$mode" in
    A|B|C) ;;
    *)
      echo "[agent-collab] 无效模式: ${mode:-空}，仅支持 A/B/C" >&2
      return 1
      ;;
  esac
  local phase
  phase="$(ac_read_field phase)"
  case "$phase" in
    planning|executing|reviewing|completed) ;;
    *)
      echo "[agent-collab] 无效阶段: ${phase:-空}" >&2
      return 1
      ;;
  esac
  local policy
  policy="$(ac_read_field approval_policy)"
  case "$policy" in
    auto|manual|hybrid) ;;
    *)
      echo "[agent-collab] 无效审批策略: ${policy:-空}" >&2
      return 1
      ;;
  esac
  return 0
}

# ── 显示状态 ────────────────────────────────────────────────────
ac_show_state() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "[agent-collab] 状态文件未初始化"
  fi
}

# ── 入口 ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  ac_init_state

  case "${2:-}" in
    show)    ac_show_state    ;;
    validate) ac_validate_state ;;
  esac
fi
