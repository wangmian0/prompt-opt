#!/bin/bash
# prompt-opt installer for Claude Code or Codex.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-claude}" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "找不到 codex CLI。" >&2; exit 1; }
    codex plugin remove prompt-opt@prompt-opt-mp >/dev/null 2>&1 || true
    codex plugin marketplace remove prompt-opt-mp >/dev/null 2>&1 || true
    codex plugin marketplace add "$DIR"
    codex plugin add prompt-opt@prompt-opt-mp
    ;;
  claude)
    command -v claude >/dev/null 2>&1 || { echo "找不到 claude CLI。" >&2; exit 1; }
    claude plugin marketplace add "$DIR" || true
    claude plugin install prompt-opt@prompt-opt-mp
    ;;
  *)
    echo "用法: ./install.sh [claude|codex]" >&2
    exit 2
    ;;
esac

if [[ "${1:-claude}" == codex ]]; then
  cat <<'EOF'

已安装到 Codex。用法:
  - 档位切换:直接输入 prompt-level auto|lite|full|ultra|off
  - 深度优化:说「用 prompt-opt 打磨一下这个 prompt」

EOF
else
  cat <<'EOF'

已安装到 Claude Code。用法:
  - 档位切换:直接输入 prompt-level auto|lite|full|ultra|off (或 /prompt-level ...)
  - 深度优化:说「用 prompt-opt 打磨一下这个 prompt」或 /prompt-opt:prompt-opt

EOF
fi
