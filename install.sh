#!/bin/bash
# prompt-opt installer — thin wrapper over Claude Code's native plugin CLI.
# Registers this repo as a local marketplace and installs the plugin, so the
# hook (prompt-level 三档) and the prompt-opt skill become available globally.
# Uninstall with: claude plugin uninstall prompt-opt@prompt-opt-mp
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

command -v claude >/dev/null 2>&1 || { echo "找不到 claude CLI,请先安装 Claude Code。" >&2; exit 1; }

claude plugin marketplace add "$DIR" || true   # idempotent: already-added is fine
claude plugin install prompt-opt@prompt-opt-mp

cat <<'EOF'

已安装。用法:
  - 档位切换:直接输入  prompt-level lite|full|ultra|off  (或 /prompt-level ...)
  - 深度优化:说「用 prompt-opt 打磨一下这个 prompt」或 /prompt-opt:prompt-opt

注意:若你之前在 ~/.claude/settings.json 里手动加过指向 hook.sh 的 UserPromptSubmit
钩子,请删掉那一条,否则规范输出会被注入两次(插件已自带该钩子)。
EOF
