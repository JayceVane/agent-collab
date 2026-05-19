#!/usr/bin/env bash
set -euo pipefail

# agent-collab 安装脚本 — 将智能体与技能安装到当前项目的 .opencode/ 目录
# 用法: bash install.sh [项目目录]
#       默认安装到当前目录

TARGET="${1:-.}"
OPENCODE_DIR="$TARGET/.opencode"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$TARGET" ]; then
  echo "错误: 目标目录不存在: $TARGET"
  exit 1
fi

mkdir -p "$OPENCODE_DIR/agents"
mkdir -p "$OPENCODE_DIR/skills"
mkdir -p "$OPENCODE_DIR/plugins/agent-collab"

cp -r "$SCRIPT_DIR/.opencode/agents/"* "$OPENCODE_DIR/agents/"
cp -r "$SCRIPT_DIR/.opencode/skills/"* "$OPENCODE_DIR/skills/"
cp -r "$SCRIPT_DIR/plugin/"* "$OPENCODE_DIR/plugins/agent-collab/"
cp "$SCRIPT_DIR/agent-collab.config.json" "$OPENCODE_DIR/agent-collab.config.json"

# FIX #5: 自动生成或更新 .opencode/opencode.json 注册插件
OPENCODE_JSON="$OPENCODE_DIR/opencode.json"
PLUGIN_ENTRY="./plugins/agent-collab"

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
        console.log('已将 agent-collab 插件注册到 $OPENCODE_JSON');
      } else {
        console.log('agent-collab 插件已在 $OPENCODE_JSON 中注册，跳过');
      }
    "
  else
    echo "警告: 无法解析 $OPENCODE_JSON，请手动添加 \"plugin\": [\"$PLUGIN_ENTRY\"]"
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
  echo "已创建 $OPENCODE_JSON 并注册 agent-collab 插件"
fi

echo ""
echo "已安装到 $OPENCODE_DIR"
echo "重启 OpenCode 或重新加载会话后生效。"
