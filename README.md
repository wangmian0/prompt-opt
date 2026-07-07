# prompt-opt

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-plugin-8A2BE2.svg)](https://code.claude.com/docs/en/plugins)

> 让 Claude Code 每条输入先自动规范化(短、口语、模糊的输入尤其受益),并按需把粗糙草稿深度打磨成正式 prompt——即装即用,`./install.sh` 一键装到 user 级。

一个让 Claude Code 输入更规范的 **Claude Code 插件**,含三个模块:

| 模块 | 是什么 | 何时起作用 |
|------|--------|-----------|
| **prompt-level 钩子** (`hook.sh`) | `UserPromptSubmit` 钩子,每条输入注入一条静态规范化指令(零 LLM) | 被动、每轮自动;分 lite/full/ultra 三档 |
| **场景模板库** (`skills/prompt-opt/templates/`) | 6 个场景的 prompt 结构骨架 + 路由索引 | 被 skill 消费;也可人工查阅 |
| **prompt-opt 技能** (`skills/prompt-opt/`) | 把一条 prompt/需求草稿深度打磨成正式 prompt 的 skill | 用户明说要优化某条 prompt 时触发 |

三者边界:**没有判断的控制操作走斜杠命令**(切档 `/prompt-level`);**有判断、有资源、产出交付物的显式流程走 skill**(`/prompt-opt`);**被动、每轮、零成本的引导走钩子**(三档规范化)。

## 安装

作为插件一键安装(注册本仓库为本地 marketplace 并安装,钩子与 skill 随即全局可用):

```bash
./install.sh
```

或临时挂载(不安装,仅本次会话有效,适合调试):

```bash
claude --plugin-dir /path/to/prompt-opt
```

卸载:`claude plugin uninstall prompt-opt@prompt-opt-mp`。

依赖:`jq`(钩子用);Claude Code。钩子本身零 LLM。

> 若你此前在 `settings.json` 里手动加过指向 `hook.sh` 的 `UserPromptSubmit` 钩子,装插件后请删掉那一条,否则「规范输出」会被注入两次。

## 目录结构(标准插件布局)

```
prompt-opt/
├── .claude-plugin/
│   ├── plugin.json          # 插件清单
│   └── marketplace.json     # 本地 marketplace(install.sh 用)
├── hooks/hooks.json         # 声明 UserPromptSubmit 钩子(指向 hook.sh)
├── hook.sh                  # 钩子本体(bash + jq,零 LLM)
├── commands/prompt-level.md # /prompt-level 切档命令兜底注册
├── skills/prompt-opt/
│   ├── SKILL.md             # 深度优化技能
│   └── templates/           # 场景模板库(skill 按 ${CLAUDE_SKILL_DIR} 读取)
├── install.sh               # 一键安装(原生 CLI 薄封装)
└── test.sh                  # 钩子确定性测试(零 LLM,秒级)
```

---

## 模块一:prompt-level 输入规范化钩子

在 agent 动手前,以 `additionalContext` 注入一条静态行为指令,要求 agent ①回复最开头先输出「规范输出:」+ 本条输入的规范化版本,②指涉环境的对象先自查目录/上下文再问,③次要偏好按默认假设一次性交付。零 LLM 调用、零额外延迟、无降级路径。短、口语、模糊的输入是重点优化对象。

注:「规范输出」显示靠模型遵从(sonnet/haiku 真机验证通过;指令措辞如实交代钩子出处——权威式命令措辞反而会触发模型的注入防御被拒绝)。指令每条输入注入一次,约 180-250 token/轮;A/B 基准只测了 full 档文案,lite(一行改写)/ultra 文案未单独跑数。

### 档位与切换

默认 **full**。档位持久化在 `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.prompt-level-state`,跨会话生效。

钩子按档位注入不同的重述指令;豁免(会话延续/斜杠命令)之外,lite 每条都改写,full/ultra 由外层模型在运行时判定如何结构化重述、是否有歧义:

| 档位 | 定位 | 行为 |
|------|------|------|
| `lite` | 日常轻 | 每条输入在回复开头输出一行规范化改写(补指代、去口语、明确对象与动作;不展开结构化字段)。 |
| `full` | 日常标准。默认 | 动手前先在回复开头把输入重述为 目标/上下文/约束/验收标准;信息不足标"假设",指涉环境可发现对象(报错/数据/文件)先自查再问,一次性交付。 |
| `ultra` | 大任务/正式 | full 之上,遇实质任务(要动手的开发/排查/优化等)把「规范输出」当作待确认的正式 prompt——产出后停下等确认再开工;有歧义先列 1–3 个澄清问题。 |
| `off` | — | 关闭,原样放行。 |

切换:直接输入下面任一命令,纯文本或斜杠形式均可(会被钩子 `block` 吞掉,不会发给 agent,只回显确认):

```
prompt-level lite|full|ultra|off
/prompt-level lite|full|ultra|off
```

不碰的输入:斜杠命令(`/` 开头)直接放行;"继续"/"好"/"修吧"这类会话延续由注入的指令要求外层模型忽略重述、直接继续。

### 降级行为

保留 never-block 语义:任何异常都静默放行原话,绝不卡住或吞掉正常输入。缺 jq、stdin 解析失败、prompt 为空 —— 一律 `exit 0` 无注入。钩子不调用外部模型,没有超时或降级路径。

---

## 模块二:场景模板库

`skills/prompt-opt/templates/` 下是 6 个 Claude Code 常见场景的 prompt 结构骨架,组织法参考 [yao-open-prompts](https://github.com/yaojingang/yao-open-prompts)(场景分类、单文件单模板、CATALOG 索引),但内容定位不同:这里是**骨架**(该场景一个好 prompt 必须回答的字段),不是可直接复制的成品文案。

- `templates/CATALOG.md` — 场景 → 文件 → 适用信号的索引,含五对易混场景的路由裁决规则。
- `templates/<场景>.md` — 每个含三节:适用信号(判定用)/ 字段骨架(基底四字段 目标·上下文·约束·验收标准 + 场景特有字段)/ 前后示例。

场景:排障修 bug、加功能、重构、调研研究、代码审查、数据报告。通用纪律写进每个模板:意图保真第一,信息不足标「假设」不虚构,多义处把读法列出来不静默选,环境可自查对象先自查再问。

模板库无需单独安装——它随 skill(模块三)一起分发,skill 按 `${CLAUDE_SKILL_DIR}` 读取;也可以直接打开查阅。

---

## 模块三:prompt-opt 深度优化技能

把一条口语/粗糙的 prompt 或需求描述深度打磨成结构完整的正式 prompt:判定场景 → 套用模板库骨架 → 产出可复制的标准 prompt 交你确认,**不执行任务本身**。适合写开工 brief、给别的 agent 的任务书、正式立项 prompt。

### 触发

- 斜杠:`/prompt-opt:prompt-opt <草稿>`(不带参数则取上一条任务型输入)。
- 自然语言:「用 prompt-opt 打磨一下」「帮我把这个需求写成正式 prompt/任务书」等。
- 边界:**只在用户明说要加工某条 prompt/需求时触发**。用户直接下达要执行的实质任务不归它——那由 ultra 档钩子做「正式化确认」(实测直接任务不会可靠触发 skill,故不让 skill 承担)。纯控制命令、轻量查询、翻译/总结、从零写 system prompt 都不触发。

装插件即自动可用,无需单独安装;插件内 skill 显示为 `/prompt-opt:prompt-opt`。

---

> 早期版本曾在钩子内冷启动 `claude -p haiku` 做改写后注入,实测延迟高、送达概率性,已改为当前的零 LLM 内联方案(由外层模型按注入指令自行重述)。
