#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
STATE_FILE="$PLUGIN_ROOT/.claude/agent-collab.local.md"

source "$PLUGIN_ROOT/scripts/state-persistence.sh" "$STATE_FILE" >/dev/null 2>&1 || exit 0

ac_init_state >/dev/null 2>&1 || true

exit 0
