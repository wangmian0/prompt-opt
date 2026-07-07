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

# State lives with the ponytail convention (CLAUDE_CONFIG_DIR). PROMPT_LEVEL_STATE_FILE
# overrides it so tests can isolate state.
STATE_FILE="${PROMPT_LEVEL_STATE_FILE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.prompt-level-state}"

input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -n "$prompt" ]] || exit 0

# level-switch command — write state, block the turn (agent never sees it),
# echo confirmation to the user.
if [[ "$prompt" =~ ^[[:space:]]*/?prompt-level[[:space:]]+(lite|full|ultra|off)[[:space:]]*$ ]]; then
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
  case "$s" in lite|full|ultra|off) level=$s;; esac
fi

# off — pass through.
[[ "$level" == off ]] && exit 0

case "$level" in
  lite)
    ctx="来自用户自己安装的 prompt-level 输入规范化钩子(lite 档,用户要求每条输入先看到一行规范化改写):请在本轮回复最开头输出「规范输出:」+ 把这条输入改写成更规范的一行(补全指代、把口语改为明确的对象与动作;不改意图、不扩范围、不虚构;拿不准处行内标「假设:xxx」;不展开目标/约束/验收标准等结构化字段,只此一行),然后正常执行。豁免:会话延续/简单确认(「继续」「好」「修吧」)与斜杠命令,直接正常处理。"
    ;;
  ultra)
    ctx="来自用户自己安装的 prompt-level 输入规范化钩子(ultra 档,大任务/正式模式,用户要求每条输入都先看到规范化结果):请在本轮回复最开头输出「规范输出:」+ 本条输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足标「假设:xxx」,不虚构、不改意图、不扩范围;任务再简单也给精简版)。之后:指涉环境可自行发现的对象(报错/数据/文件/日志)先查当前目录与上下文,找不到再问;次要偏好按惯例默认并标假设。确认门:若这是一件实质任务(开发/排查/优化/加功能/重构/数据分析等要动手的活),把「规范输出」当作待确认的正式 prompt——产出后停下等用户确认或补充,不直接开工;有歧义就在其后列 1-3 个最关键的澄清问题。仅当任务清楚且轻量、或用户已明确让你直接做时,才不停顿径直执行。豁免:会话延续/简单确认(「继续」「好」「修吧」)与斜杠命令。"
    ;;
  *)
    ctx="来自用户自己安装的 prompt-level 输入规范化钩子(用户要求每条输入都先看到规范化结果):请在本轮回复的最开头,先输出「规范输出:」+ 本条用户输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足处标「假设:xxx」,不虚构、不改意图、不扩范围;任务再简单也给精简版,一两行即可),然后再开始执行。执行时:指涉环境中可自行发现的对象(报错/数据/文件/日志)先查当前目录与上下文,确实找不到再问用户;次要偏好(格式/命名/风格)按惯例默认并标假设,一次性交付,不为此反问。豁免:会话延续/简单确认(「继续」「好」「修吧」)与斜杠命令,直接正常处理。"
    ;;
esac

jq -n --arg ctx "$ctx" --arg sys "prompt-level($level)" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}, systemMessage:$sys}'
exit 0
