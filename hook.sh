#!/bin/bash
# prompt-level — UserPromptSubmit hook (inline engine). Zero-LLM: inject a static
# instruction telling the OUTER model to restate the input as a structured
# prompt (at the top of its reply) before acting. No inner model call, no
# watchdog, no degrade path.
#
# Never-block contract: any failure — missing jq, parse error, empty prompt —
# exits 0 with no output so the original prompt proceeds unchanged.
set -u

command -v jq >/dev/null 2>&1 || exit 0

# Tests can override the state file. Codex and Claude otherwise keep independent modes.
if [[ -n "${PROMPT_LEVEL_STATE_FILE:-}" ]]; then
  STATE_FILE="$PROMPT_LEVEL_STATE_FILE"
elif [[ -n "${PLUGIN_DATA:-}" ]]; then
  STATE_FILE="$PLUGIN_DATA/.prompt-level-state"
elif [[ -n "${CODEX_THREAD_ID:-}${CODEX_CI:-}" ]]; then
  STATE_FILE="${CODEX_HOME:-$HOME/.codex}/.prompt-level-state"
else
  STATE_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.prompt-level-state"
fi

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -n "$prompt" ]] || exit 0

# level-switch command — write state, block the turn (agent never sees it),
# echo confirmation to the user.
if [[ "$prompt" =~ ^[[:space:]]*/?prompt-level[[:space:]]+(auto|lite|full|ultra|off)[[:space:]]*$ ]]; then
  new="${BASH_REMATCH[1]}"
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
  if { printf '%s' "$new" > "$STATE_FILE"; } 2>/dev/null; then
    jq -n --arg r "prompt-level 已切至 $new" '{decision:"block",reason:$r}'
  else
    jq -n --arg r "prompt-level 切档失败:状态文件不可写 ($STATE_FILE)" '{decision:"block",reason:$r}'
  fi
  exit 0
fi

# slash command — pass through untouched.
[[ "$prompt" == /* ]] && exit 0

# level (default full; unknown/empty state falls back to full).
level=full
if [[ -f "$STATE_FILE" ]]; then
  s=$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null)
  case "$s" in auto|lite|full|ultra|off) level=$s;; esac
fi

# off — pass through.
[[ "$level" == off ]] && exit 0

case "$level" in
  auto)
    ctx="用户自装 prompt-level 钩子(auto):按输入复杂度自选档。简单(单一动作/问答/确认/延续)→ 直接做,不重述。中等(口语或指代不全,意图单一)→ 开头一行规范化改写。复杂(多文件/多步/多解读/只给目标)→ 开头「规范输出:」目标/上下文/约束/验收,缺信息标「假设:」。重大(不可逆/对外/动共享基建)→ 同复杂档,但产出后停下等确认再开工,有歧义列 1-3 问。拿不准往高一档。豁免:斜杠命令。"
    ;;
  lite)
    ctx="用户自装 prompt-level 钩子(lite):回复最开头输出「规范输出:」+ 把本条输入改写成更规范的一行(补全指代、口语转明确对象与动作;不改意图、不扩范围、不虚构,拿不准处标「假设:xxx」;只此一行,不展开目标/约束等字段),然后正常执行。执行中发现该解读与环境证据(报错/文件/数据)冲突,以证据为准并明说修正。豁免:会话延续/简单确认(「继续」「好」)与斜杠命令。"
    ;;
  ultra)
    ctx="用户自装 prompt-level 钩子(ultra,大任务/正式模式):回复最开头输出「规范输出:」+ 本条输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足标「假设:xxx」,不虚构、不改意图、不扩范围;疑似用户自猜的实现手段标「可选建议」,把目标写足;任务再简单也给精简版)。之后:环境可自查对象(报错/数据/文件/日志)先查再问;次要偏好按惯例默认并标假设。确认门:实质任务(开发/排查/优化/加功能/重构/数据分析等)把「规范输出」当待确认的正式 prompt——产出后停下等用户确认,不直接开工;有歧义列 1-3 个最关键的澄清问题。仅当任务清楚且轻量、或用户明确让直接做,才径直执行。执行中发现规范输出的解读与环境证据冲突,以证据为准并明说修正,不硬圆。豁免:会话延续/简单确认与斜杠命令。"
    ;;
  *)
    ctx="用户自装 prompt-level 钩子(full):回复最开头输出「规范输出:」+ 本条输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足处标「假设:xxx」,不虚构、不改意图、不扩范围;任务再简单也给一两行精简版),然后开始执行。执行时:环境可自查对象(报错/数据/文件/日志)先查再问;次要偏好(格式/命名/风格)按惯例默认并标假设,一次性交付;发现规范输出的解读与环境证据冲突,以证据为准并明说修正,不硬圆。豁免:会话延续/简单确认(「继续」「好」)与斜杠命令。"
    ;;
esac

jq -n --arg ctx "$ctx" --arg sys "prompt-level($level)" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}, systemMessage:$sys}'
exit 0
