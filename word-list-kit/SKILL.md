---
name: yomiori-word-list
description: 按 Yomiori v1 契约制作、标注来源并校验英语或日语 JSON 词表。
---

# 生成 Yomiori 词表

先阅读本技能同目录的 [format.md](format.md) 与 [word-list.schema.json](word-list.schema.json)，参考 [examples/study-starter.json](examples/study-starter.json)。应用中的校验与合并逻辑位于 `Yomiori/WordListDocument.swift`；发现文档、Schema 与实现之间有冲突时先明确冲突，不改写应用或格式来迁就文件。

1. 收集必要事实：主题、受众、标题、目标语言（仅 en 或 ja）、翻译语言标签、词表 ID、词条范围、真实来源、适用许可、是否改编以及是否允许 AI 原创。可从用户已提供资料和可核验来源补全；不要反复索要已知信息。不得凭空声称查询过词典、访问过页面或取得媒体许可。
2. 为词表及词条建立可持久化的 ASCII ID。沿用用户已有 ID，内容更新不能更换身份；同文件 entry ID 唯一，大小写敏感，不能使用保留词表 ID ielts。身份为词表 ID 加词条 ID，与词序无关。
3. 区分经过实际核验的词典资料、人工原创和 AI 原创。source 的所有字段都要提供：name、url、license、licenseURL、attribution、modified、contentType；name、license、attribution 至少包含一个非空白字符。标题也必须有非空白内容，entries 至少一条，不能交付空词表。仅实际来自词典的内容才能标为 dictionary；AI 自行编写的释义、翻译、句子与建议级别标为 ai-generated，并在署名中明确未经独立核验。不能把 AI 生成伪装成用户手写或已获词典背书。来源和许可无法诚实说明时不要伪造链接或权利，应先解决必要事实。
4. 不捏造词义事实、引文、发音、媒体或来源。若用户允许 AI 原创，可编写合理原创释义与例句，并明确 AI 来源和未核验状态；不能断言它们来自真实词典。source.url 可使用真实的生成工具项目主页，但必须明确这不是该词条的刊载地址。示例使用 https://openai.com/ 并明确其含义；不要盲目复制示例的 CC0 许可到他人内容。人工原创可提供真实作者/项目 HTTPS 页和实际授权；借用资料必须核实条款与署名。Word Atlas 仓库仅可用于实际从该库取得且已核验的资料，不可作为 AI 内容来源。
5. 不知道可选数据就省略：无需发音、同反义词、词族、图片或音频。media 一旦给出，必须是实际核验过、允许使用的 HTTPS 链接；不能根据词条拼接猜测资源路径，也不能用占位 URL。没有可验证媒体时省略 media。不要因必填字段而捏造释义；senses 至少一项且 definition 非空，不允许空 meanings（此格式根本没有 meanings 属性）。无法提供释义的词条暂不收录。examples 可空数组，translation 可空字符串，未知 level 可用空字符串。
6. 保留词形变化的自然例句。例如 motivate 的例句可以使用 motivates；不要为了匹配原形而损坏语法。所有字段严格遵守 Schema，未知属性、null 和超限内容都不能交付。
7. 将完整文档保存为 `.json` 文件。在项目目录执行 `python3 word-list-kit/validate.py path/to/output.json`（或使用本技能目录下 validate.py 的实际路径），修复错误后再运行，直到退出码 0。若已装 jsonschema 可做 format.md 中的附加 Schema 检查，但不能代替 CLI 的 ID 去重、导入保留值和大小限制检查。Schema 为审计内置文件允许 ielts；CLI 的 --allow-builtin 仅供检查应用随附的 Yomiori/word-atlas.json，不得用于生成文件或绕过导入限制。验证是只读，不访问网络，不能证明内容或媒体真实性。
8. 只输出实际生成且通过校验的 JSON 文件附件/文件链接；用户明确要求内联时仅输出完整 JSON 原文。不要把解释、校验日志、Markdown 围栏或虚构下载链接混进交付内容。无法落盘时诚实说明限制，不得声称已创建文件。

不要承诺应用中尚未核验的导入功能。已有词表合并应保留 ID、跳过或更新重复内容、保留所有学习排期，不删除文件中未出现的旧条目，不改已有词表的语言。导入不自动创建卡片；后续 Add Cards 不重新排期重复卡片。该技能只生成与验证词表，不负责写入应用数据。
