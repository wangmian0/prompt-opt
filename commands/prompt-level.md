---
description: 切换 prompt-level 输入标准化档位 (auto|lite|full|ultra|off)
argument-hint: auto|lite|full|ultra|off
---

用户执行了 /prompt-level $ARGUMENTS 切换档位。斜杠形式被展开成本文,钩子拦不到,需你代切。

请只做以下事,不做其它动作:

1. 取 `$ARGUMENTS` 第一个词。若不是 auto / lite / full / ultra / off 之一,回一句
   「合法档位:auto|lite|full|ultra|off」,不写文件。
2. 是,则覆盖写入档位状态文件(纯小写、无空格无换行):

   ```bash
   printf '%s' <档位> > "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.prompt-level-state"
   ```

3. 回一句「prompt-level 已切至 <档位>」。

注:纯文本 `prompt-level <档位>`(不带斜杠)由钩子零 LLM 直接切,更快;斜杠形式才走本文由你代写。
