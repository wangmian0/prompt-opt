#!/bin/bash
# prompt-level test suite — inline engine is zero-LLM and fully deterministic,
# so no real model calls / retries. State isolated via PROMPT_LEVEL_STATE_FILE
# (never touches ~/.claude). Each assertion prints PASS/FAIL; any failure exits
# non-zero. All checks complete in sub-second.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook.sh"
STATE_DIR="$(mktemp -d)"
export PROMPT_LEVEL_STATE_FILE="$STATE_DIR/.prompt-level-state"
STATE_FILE="$PROMPT_LEVEL_STATE_FILE"
FAILED=0
cleanup() { rm -rf "$STATE_DIR"; }
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILED=1; }
check() { if [[ "$1" == 0 || "$1" == true ]]; then pass "$2"; else fail "$2"; fi; }
run() { printf '%s' "$1" | bash "$HOOK"; }
jqok() { printf '%s' "$1" | jq -e "$2" >/dev/null 2>&1 && printf true || printf false; }

printf '=== a. full task input -> valid JSON + additionalContext + systemMessage ===\n'
OUT=$(run '{"prompt":"给 fetch 加个重试"}')
check "$(jqok "$OUT" '.')" "a1 output is valid JSON"
check "$(jqok "$OUT" '.hookSpecificOutput.hookEventName == "UserPromptSubmit"')" "a2 hookEventName correct"
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("结构化标准版本")')" "a3 additionalContext restates structured"
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("规范输出")')" "a3b full requires 规范输出 prefix"
check "$(jqok "$OUT" '.systemMessage == "prompt-level(full)"')" "a4 systemMessage == prompt-level(full)"

printf '=== b. slash command -> no output ===\n'
OUT=$(run '{"prompt":"/help"}')
[[ -z "$OUT" ]] && check 0 "b1 slash command -> no injection" || check 1 "b1 slash command -> no injection (got: $OUT)"

printf '=== c. switch commands + per-level texts ===\n'
OUT=$(run '{"prompt":"prompt-level lite"}')
check "$(jqok "$OUT" '.decision == "block"')" "c1 text switch blocked"
[[ "$(cat "$STATE_FILE" 2>/dev/null)" == "lite" ]] && check 0 "c2 state -> lite" || check 1 "c2 state -> lite"
OUT=$(run '{"prompt":"帮我优化一下那个函数"}')
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("改写成更规范的一行")')" "c3 lite context asks one-line rewrite"
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("结构化标准版本") | not')" "c3b lite context has no structured-restate wording"
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("斜杠命令")')" "c3c lite context keeps exemptions"
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("假设")')" "c3d lite context keeps 假设 marking"
OUT=$(run '{"prompt":"/prompt-level ultra"}')
check "$(jqok "$OUT" '.decision == "block"')" "c4 slash switch blocked"
[[ "$(cat "$STATE_FILE" 2>/dev/null)" == "ultra" ]] && check 0 "c5 state -> ultra" || check 1 "c5 state -> ultra"
OUT=$(run '{"prompt":"帮我优化一下那个函数"}')
check "$(jqok "$OUT" '.hookSpecificOutput.additionalContext | contains("澄清问题")')" "c6 ultra context contains 澄清问题"
OUT=$(run '{"prompt":"prompt-level off"}')
[[ "$(cat "$STATE_FILE" 2>/dev/null)" == "off" ]] && check 0 "c7 state -> off" || check 1 "c7 state -> off"
OUT=$(run '{"prompt":"帮我看看那个报错"}')
[[ -z "$OUT" ]] && check 0 "c8 off -> pass-through no injection" || check 1 "c8 off -> pass-through (got: $OUT)"

printf '=== d. malformed / empty prompt -> exit 0 no output ===\n'
OUT=$(printf 'not json' | bash "$HOOK"); RC=$?
[[ $RC -eq 0 && -z "$OUT" ]] && check 0 "d1 malformed stdin -> exit 0 no output" || check 1 "d1 malformed stdin (rc=$RC out=$OUT)"
OUT=$(run '{"prompt":""}'); RC=$?
[[ $RC -eq 0 && -z "$OUT" ]] && check 0 "d2 empty prompt -> exit 0 no output" || check 1 "d2 empty prompt (rc=$RC out=$OUT)"

printf '=== e. illegal state value -> fall back to full ===\n'
printf 'garbage' > "$STATE_FILE"
OUT=$(run '{"prompt":"给 fetch 加个重试"}')
check "$(jqok "$OUT" '.systemMessage == "prompt-level(full)"')" "e1 illegal state -> full"

printf '\n'
if [[ $FAILED -eq 0 ]]; then printf 'ALL PASS\n'; else printf 'SOME FAILED\n'; fi
exit $FAILED
