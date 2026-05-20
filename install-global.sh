#!/usr/bin/env bash
set -euo pipefail

# agent-collab 全局安装脚本 — 将插件安装到 OpenCode 全局配置目录
#
# 用法:
#   bash install-global.sh                          # 安装到默认全局目录 (~/.config/opencode)
#   bash install-global.sh /path/to/global-dir      # 安装到指定目录
#
# 说明:
#   将 agent-collab 的 Agents、Skills、JS 插件、默认配置和辅助脚本
#   安装到 OpenCode 全局配置目录，使审批门控、Git 保护等能力在所有项目中生效。
#   每个项目的协作状态和配置仍然按项目独立。

# ---------------------------------------------------------------------------
# 变量
# ---------------------------------------------------------------------------

GLOBAL_DIR="${1:-$HOME/.config/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ENTRY="./plugins/agent-collab"

# ---------------------------------------------------------------------------
# 颜色辅助函数
# ---------------------------------------------------------------------------

green()  { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
cyan()   { echo -e "\033[36m$*\033[0m"; }
magenta() { echo -e "\033[35m$*\033[0m"; }

# ---------------------------------------------------------------------------
# 开头说明
# ---------------------------------------------------------------------------

echo ""
magenta "============================================================"
magenta "  agent-collab 全局安装"
magenta "============================================================"
echo ""
cyan "全局安装说明："
echo "  - JS 插件的审批门控和 Git 保护将在所有项目中生效"
echo "  - 每个项目的协作状态和配置 (agent-collab.config.json) 仍然按项目独立"
echo "  - 如需自定义某项目的配置，在该项目的 .opencode/ 目录下创建"
echo "    agent-collab.config.json 即可覆盖全局默认"
echo "  - 安装完成后需要重启 OpenCode"
echo ""

# ---------------------------------------------------------------------------
# 步骤 1：创建目标目录结构
# ---------------------------------------------------------------------------

cyan "[1/4] 创建全局目录结构..."

mkdir -p "$GLOBAL_DIR/agents"
mkdir -p "$GLOBAL_DIR/skills"
mkdir -p "$GLOBAL_DIR/plugins/agent-collab"
mkdir -p "$GLOBAL_DIR/scripts/agent-collab"

green "  -> 目录结构已就绪: $GLOBAL_DIR"

# ---------------------------------------------------------------------------
# 步骤 2：复制组件
# ---------------------------------------------------------------------------

cyan "[2/4] 复制组件到全局目录..."

# Agents
if [ -d "$SCRIPT_DIR/.opencode/agents" ] && ls "$SCRIPT_DIR/.opencode/agents/"* >/dev/null 2>&1; then
  cp -r "$SCRIPT_DIR/.opencode/agents/"* "$GLOBAL_DIR/agents/"
  green "  -> Agents 已安装"
else
  yellow "  -> 跳过 Agents（源目录为空或不存在）"
fi

# Skills
if [ -d "$SCRIPT_DIR/.opencode/skills" ] && ls "$SCRIPT_DIR/.opencode/skills/"* >/dev/null 2>&1; then
  cp -r "$SCRIPT_DIR/.opencode/skills/"* "$GLOBAL_DIR/skills/"
  green "  -> Skills 已安装"
else
  yellow "  -> 跳过 Skills（源目录为空或不存在）"
fi

# JS Plugin
if [ -d "$SCRIPT_DIR/plugin" ] && ls "$SCRIPT_DIR/plugin/"* >/dev/null 2>&1; then
  cp -r "$SCRIPT_DIR/plugin/"* "$GLOBAL_DIR/plugins/agent-collab/"
  green "  -> JS Plugin 已安装"
else
  yellow "  -> 跳过 JS Plugin（源目录为空或不存在）"
fi

# 默认配置（仅当目标不存在时复制，避免覆盖用户已有配置）
if [ -f "$SCRIPT_DIR/agent-collab.config.json" ]; then
  if [ -f "$GLOBAL_DIR/agent-collab.config.json" ]; then
    yellow "  -> 默认配置已存在，跳过（不覆盖）"
  else
    cp "$SCRIPT_DIR/agent-collab.config.json" "$GLOBAL_DIR/agent-collab.config.json"
    green "  -> 默认配置已安装"
  fi
else
  yellow "  -> 跳过默认配置（源文件不存在）"
fi

# Scripts（可选）
if [ -d "$SCRIPT_DIR/scripts" ] && ls "$SCRIPT_DIR/scripts/"* >/dev/null 2>&1; then
  cp -r "$SCRIPT_DIR/scripts/"* "$GLOBAL_DIR/scripts/agent-collab/"
  green "  -> Scripts 已安装"
else
  yellow "  -> 跳过 Scripts（源目录为空或不存在）"
fi

# Commands（可选）
if [ -d "$SCRIPT_DIR/commands" ] && ls "$SCRIPT_DIR/commands/"* >/dev/null 2>&1; then
  mkdir -p "$GLOBAL_DIR/commands"
  cp -r "$SCRIPT_DIR/commands/"* "$GLOBAL_DIR/commands/"
  green "  -> Commands 已安装"
else
  yellow "  -> 跳过 Commands（源目录为空或不存在）"
fi

# ---------------------------------------------------------------------------
# 步骤 3：注册插件到全局 opencode.json
# ---------------------------------------------------------------------------

cyan "[3/4] 注册插件到全局 opencode.json..."

OPENCODE_JSON="$GLOBAL_DIR/opencode.json"

if [ -f "$OPENCODE_JSON" ]; then
  # 已有配置文件：用 node 合并 plugin 数组
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs = require('fs');
      const f = '$OPENCODE_JSON';
      let cfg;
      try { cfg = JSON.parse(fs.readFileSync(f, 'utf8')); }
      catch { cfg = {}; }
      if (!cfg.plugin) cfg.plugin = [];
      if (!cfg.plugin.includes('$PLUGIN_ENTRY')) {
        cfg.plugin.push('$PLUGIN_ENTRY');
        fs.writeFileSync(f, JSON.stringify(cfg, null, 2));
        console.log('\x1b[32m  -> 已将 agent-collab 插件注册到 $OPENCODE_JSON\x1b[0m');
      } else {
        console.log('\x1b[33m  -> agent-collab 插件已在 $OPENCODE_JSON 中注册，跳过\x1b[0m');
      }
    "
  else
    yellow "  警告: 无法解析 $OPENCODE_JSON，请手动添加 \"plugin\": [\"$PLUGIN_ENTRY\"]"
  fi
else
  # 无配置文件：创建新的
  cat > "$OPENCODE_JSON" <<OPCODEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugin": [
    "$PLUGIN_ENTRY"
  ]
}
OPCODEOF
  green "  -> 已创建 $OPENCODE_JSON 并注册 agent-collab 插件"
fi

# ---------------------------------------------------------------------------
# 步骤 4：完成
# ---------------------------------------------------------------------------

cyan "[4/4] 安装完成"
echo ""
green "agent-collab 已全局安装到: $GLOBAL_DIR"
echo ""
yellow "请重启 OpenCode 以使插件生效。"
echo ""
