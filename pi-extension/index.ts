/**
 * pi-extension for prompt-opt — prompt-level input normalization.
 * Zero-LLM: injects a static instruction telling the model to restate
 * user input as a structured prompt before acting.
 *
 * Migrated from Claude Code UserPromptSubmit hook (hook.sh).
 *
 * State file: ~/.claude/.prompt-level-state (shared with Claude hook).
 *
 * Install: symlink or copy this file + package.json into
 *   ~/.pi/agent/extensions/prompt-level/ or add as pi package.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

const HOME = homedir();
const STATE_FILE = process.env.PROMPT_LEVEL_STATE_FILE ||
  join(HOME, ".claude", ".prompt-level-state");

type Level = "lite" | "full" | "ultra" | "off";

function readLevel(): Level {
  try {
    if (!existsSync(STATE_FILE)) return "full";
    const s = readFileSync(STATE_FILE, "utf-8").replace(/\s/g, "");
    if (["lite", "full", "ultra", "off"].includes(s)) return s as Level;
  } catch { /* ignore */ }
  return "full";
}

function writeLevel(level: Level): boolean {
  try {
    mkdirSync(dirname(STATE_FILE), { recursive: true });
    writeFileSync(STATE_FILE, level);
    return true;
  } catch {
    return false;
  }
}

// Static instruction texts, from hook.sh
const INSTRUCTIONS: Record<Exclude<Level, "off">, string> = {
  lite:
    "用户自装 prompt-level 钩子(lite):回复最开头输出「规范输出:」+ 把本条输入改写成更规范的一行(补全指代、口语转明确对象与动作;不改意图、不扩范围、不虚构,拿不准处标「假设:xxx」;只此一行,不展开目标/约束等字段),然后正常执行。执行中发现该解读与环境证据(报错/文件/数据)冲突,以证据为准并明说修正。豁免:会话延续/简单确认(「继续」「好」)与斜杠命令。",

  full:
    "用户自装 prompt-level 钩子(full):回复最开头输出「规范输出:」+ 本条输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足处标「假设:xxx」,不虚构、不改意图、不扩范围;任务再简单也给一两行精简版),然后开始执行。执行时:环境可自查对象(报错/数据/文件/日志)先查再问;次要偏好(格式/命名/风格)按惯例默认并标假设,一次性交付;发现规范输出的解读与环境证据冲突,以证据为准并明说修正,不硬圆。豁免:会话延续/简单确认(「继续」「好」)与斜杠命令。",

  ultra:
    "用户自装 prompt-level 钩子(ultra,大任务/正式模式):回复最开头输出「规范输出:」+ 本条输入的结构化标准版本(目标/上下文/约束/验收标准;信息不足标「假设:xxx」,不虚构、不改意图、不扩范围;疑似用户自猜的实现手段标「可选建议」,把目标写足;任务再简单也给精简版)。之后:环境可自查对象(报错/数据/文件/日志)先查再问;次要偏好按惯例默认并标假设。确认门:实质任务(开发/排查/优化/加功能/重构/数据分析等)把「规范输出」当待确认的正式 prompt——产出后停下等用户确认,不直接开工;有歧义列 1-3 个最关键的澄清问题。仅当任务清楚且轻量、或用户明确让直接做,才径直执行。执行中发现规范输出的解读与环境证据冲突,以证据为准并明说修正,不硬圆。豁免:会话延续/简单确认与斜杠命令。",
};

// Patterns for conversation continuations that should skip normalization
const CONTINUATION_RE = /^(继续|好|行|OK|ok|嗯|对|是的|可以|来吧|go on|go ahead|next|下一步)\s*[!！。.]?$/i;
const SLASH_RE = /^\s*\//;

function shouldSkip(prompt: string): boolean {
  return CONTINUATION_RE.test(prompt.trim()) || SLASH_RE.test(prompt);
}

export default function (pi: ExtensionAPI) {
  // ── prompt-level command (handled before agent sees it) ──
  pi.registerCommand("prompt-level", {
    description: "切换 prompt 规范化级别 (lite|full|ultra|off)",
    handler: async (args, ctx) => {
      const level = args?.trim() as Level;
      if (!["lite", "full", "ultra", "off"].includes(level)) {
        ctx.ui.notify(
          `用法: /prompt-level lite|full|ultra|off (当前: ${readLevel()})`,
          "error"
        );
        return;
      }
      if (writeLevel(level)) {
        ctx.ui.notify(`prompt-level 已切至 ${level}`, "info");
      } else {
        ctx.ui.notify(
          `prompt-level 切档失败: 状态文件不可写 (${STATE_FILE})`,
          "error"
        );
      }
    },
  });

  // ── Inject prompt-opt instruction as hidden user message ──
  // Uses display:false so only the model sees it, not the user.
  const PREFIX: Record<Exclude<Level, "off">, string> = {
    lite:  "回复最开头输出「规范输出:」+ 一行改写(补全指代、明确对象与动作;不改意图),然后正常执行。用户输入:",
    full:  "回复最开头输出「规范输出:」+ 结构化改写(目标/上下文/约束/验收标准;信息不足标假设;任务简单也给精简版),然后开始执行。用户输入:",
    ultra: "回复最开头输出「规范输出:」+ 完整结构化改写(目标/上下文/约束/验收标准;信息不足标假设;用户自猜手段降为可选建议)。产出后停下等用户确认再执行。用户输入:",
  };

  pi.on("before_agent_start", async (event, ctx) => {
    const level = readLevel();
    if (level === "off") return;
    const text = event.prompt?.trim() ?? "";
    if (shouldSkip(text)) return;
    const prefix = PREFIX[level];
    if (!prefix) return;

    return {
      message: {
        customType: "prompt-level",
        content: `${prefix} ${text}`,
        display: false,
      },
    };
  });
}
