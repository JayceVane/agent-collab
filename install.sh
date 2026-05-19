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

echo "已安装到 $OPENCODE_DIR"
echo "重启 OpenCode 或重新加载会话后生效。"
