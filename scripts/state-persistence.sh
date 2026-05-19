#!/usr/bin/env bash
set -euo pipefail

# FIX #4: 状态文件统一为 JSON 格式（与插件 index.js 的 agent-collab-state.json 一致）
STATE_FILE="${1:-.opencode/agent-collab-state.json}"

# ── JSON 读写辅助 ──────────────────────────────────────────────
# 使用简单的 sed/node 解析，避免依赖 jq

# 检查 node 是否可用（OpenCode 项目通常有 Node.js）
has_node() {
  command -v node >/dev/null 2>&1
}

# 读取 JSON 字段（标量值）
# 用法: ac_read_field <字段名>
ac_read_field() {
  local field="$1"
  if [ ! -f "$STATE_FILE" ]; then
    echo ""
    return 1
  fi

  if has_node; then
    node -e "
      try {
        const d = JSON.parse(require('fs').readFileSync('$STATE_FILE','utf8'));
        const v = d['${field}'];
        if (Array.isArray(v)) { process.stdout.write(JSON.stringify(v)); }
        else { process.stdout.write(String(v ?? '')); }
      } catch { process.stdout.write(''); }
    " 2>/dev/null
  else
    # 回退：简单 sed 解析（仅支持顶层标量）
    sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\{0,1\\}\\([^,\"}\\]*\\)\"\\{0,1\\}.*/\\1/p" "$STATE_FILE" | head -1
  fi
}

# 写入 JSON 字段（标量值）
# 用法: ac_write_field <字段名> <新值>
ac_write_field() {
  local field="$1"
  local value="$2"
  if [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 错误：状态文件不存在，请先初始化" >&2
    return 1
  fi

  if has_node; then
    local tmp
    tmp="$(mktemp)"
    node -e "
      const fs = require('fs');
      const d = JSON.parse(fs.readFileSync('$STATE_FILE','utf8'));
      d['${field}'] = '${value}';
      fs.writeFileSync('$tmp', JSON.stringify(d, null, 2));
    " 2>/dev/null
    mv "$tmp" "$STATE_FILE"
  else
    echo "[agent-collab] 错误：需要 Node.js 来操作 JSON 状态文件" >&2
    return 1
  fi
}

# ── 追加审批项 ──────────────────────────────────────────────────
# 用法: ac_add_approval <描述>
ac_add_approval() {
  local desc="$1"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 'unknown')"
  if [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 错误：状态文件不存在" >&2
    return 1
  fi

  if has_node; then
    local tmp
    tmp="$(mktemp)"
    node -e "
      const fs = require('fs');
      const d = JSON.parse(fs.readFileSync('$STATE_FILE','utf8'));
      if (!d.pending_approvals) d.pending_approvals = [];
      d.pending_approvals.push({ desc: \"${desc}\", status: 'pending', ts: '${ts}' });
      fs.writeFileSync('$tmp', JSON.stringify(d, null, 2));
    " 2>/dev/null
    mv "$tmp" "$STATE_FILE"
  else
    echo "[agent-collab] 错误：需要 Node.js 来操作 JSON 状态文件" >&2
    return 1
  fi
}

# ── 解决审批项 ──────────────────────────────────────────────────
# 用法: ac_resolve_approval <approved|rejected>
ac_resolve_approval() {
  local verdict="$1"
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi

  if has_node; then
    local tmp
    tmp="$(mktemp)"
    node -e "
      const fs = require('fs');
      const d = JSON.parse(fs.readFileSync('$STATE_FILE','utf8'));
      if (d.pending_approvals) {
        const item = d.pending_approvals.find(i => i.status === 'pending');
        if (item) item.status = '${verdict}';
      }
      fs.writeFileSync('$tmp', JSON.stringify(d, null, 2));
    " 2>/dev/null
    mv "$tmp" "$STATE_FILE"
  fi
}

# ── 统计待审批数量 ──────────────────────────────────────────────
ac_pending_count() {
  if [ ! -f "$STATE_FILE" ]; then
    echo 0
    return
  fi

  if has_node; then
    node -e "
      try {
        const d = JSON.parse(require('fs').readFileSync('$STATE_FILE','utf8'));
        const c = (d.pending_approvals || []).filter(i => i.status === 'pending').length;
        process.stdout.write(String(c));
      } catch { process.stdout.write('0'); }
    " 2>/dev/null
  else
    echo 0
  fi
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

# ── 迁移 ──────────────────────────────────────────────────────
ac_migrate_state() {
  # 从旧的 .claude/agent-collab.local.md (YAML) 迁移到 JSON
  local old_file=".claude/agent-collab.local.md"
  if [ -f "$old_file" ] && [ ! -f "$STATE_FILE" ]; then
    echo "[agent-collab] 检测到旧格式状态文件，正在迁移..."
    ac_init_state
    # 尝试从 YAML 读取关键字段并写入 JSON
    if has_node; then
      local mode_val
      mode_val="$(sed -n 's/^mode: *//p' "$old_file" | head -1)"
      [ -n "$mode_val" ] && ac_write_field mode "$mode_val"

      local phase_val
      phase_val="$(sed -n 's/^phase: *//p' "$old_file" | head -1)"
      [ -n "$phase_val" ] && ac_write_field phase "$phase_val"

      local policy_val
      policy_val="$(sed -n 's/^approval_policy: *//p' "$old_file" | head -1)"
      [ -n "$policy_val" ] && ac_write_field approval_policy "$policy_val"
    fi
    echo "[agent-collab] 迁移完成。旧文件保留在 $old_file"
  fi
}

# ── 初始化 ──────────────────────────────────────────────────────
ac_init_state() {
  # 如果已存在则合并新字段（不覆盖）
  if [ -f "$STATE_FILE" ] && has_node; then
    local tmp
    tmp="$(mktemp)"
    node -e "
      const fs = require('fs');
      const defaults = {
        enabled: true,
        mode: 'A',
        phase: 'planning',
        approval_policy: 'hybrid',
        pending_approvals: [],
        completed_tasks: [],
        active_agents: [],
        git_main_branch_protection: true,
        git_require_clean_checkout: true,
        git_block_on_pending_approvals: true,
        git_require_review_before_merge: true,
      };
      let d;
      try { d = JSON.parse(fs.readFileSync('$STATE_FILE','utf8')); }
      catch { d = {}; }
      for (const [k, v] of Object.entries(defaults)) {
        if (!(k in d)) d[k] = v;
      }
      fs.writeFileSync('$tmp', JSON.stringify(d, null, 2));
    " 2>/dev/null
    mv "$tmp" "$STATE_FILE"
    return 0
  fi

  # 全新初始化
  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" <<'STATEOF'
{
  "enabled": true,
  "mode": "A",
  "phase": "planning",
  "approval_policy": "hybrid",
  "pending_approvals": [],
  "completed_tasks": [],
  "active_agents": [],
  "git_main_branch_protection": true,
  "git_require_clean_checkout": true,
  "git_block_on_pending_approvals": true,
  "git_require_review_before_merge": true
}
STATEOF
}

# ── 验证状态文件 ────────────────────────────────────────────────
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
  ac_migrate_state
  ac_init_state

  case "${2:-}" in
    show)     ac_show_state    ;;
    validate) ac_validate_state ;;
  esac
fi
