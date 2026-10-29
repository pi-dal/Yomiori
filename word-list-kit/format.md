# Kotoba 词表文件格式（v1）

本工具包依据项目 `.airbuild/wordlist-contract.md` 制作；契约是实现目标，不代表导入界面或所有行为已经上线。工具仅检查文件，不读写应用数据。文件应保存为 UTF-8、扩展名 `.json`，不要交付 Markdown 代码块、JavaScript 或压缩包作为词表。

参考：[Schema](word-list.schema.json)、[完整三词示例](examples/study-starter.json)、[代理技能](SKILL.md)。示例是英语 → 简体中文，包含 motivate / motivates 的词形变化；没有引用词典、没有媒体，CEFR 级别也是 AI 建议。

## 外层结构

所有对象均拒绝未知属性，包括 source、词条、释义、例句、pronunciations 和 media。所有下列外层字段必须出现：

| 字段 | 约束 |
| --- | --- |
| format | 固定 `kotoba.wordlist` |
| version | 整数 `1` |
| id | 稳定词表标识；ASCII 字母或数字开头，后续为字母、数字、`.`、`_`、`-`，总长 1–80；保留值 `ielts` 禁止导入 |
| title | 至少包含一个非空白字符的字符串，最多 120 字符 |
| language | 仅 `en`、`ja`（学习目标语言） |
| translationLanguage | 满足 `^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$` 的标签，如 `zh-Hans`；仅语法检查，不证明标签已经注册 |
| source | 下表中的全部字段 |
| entries | 数组，1–20,000 条，空词表拒绝导入 |

文件大小上限为 20 MiB（20,971,520 字节），包含空格、换行。通用字符串最多 10,000 个 Unicode 字符；不是 UTF-8 字节数。ID 按大小写区分，身份键为 `(document.id, entry.id)`；修改内容时保留 ID，禁止仅凭显示顺序重新编号。

## source：来源和许可

`name`、`url`、`license`、`licenseURL`、`attribution`、`modified`、`contentType` 全部必填。前五项为字符串；`url` 与 `licenseURL` 必须是安全的绝对 HTTPS URL；`modified` 是布尔值；`contentType` 仅为 `ai-generated`、`dictionary` 或 `user-authored`。

真实词典资料应指向实际来源和许可，核对署名、改编授权与 modified。人工原创可用真实作者/项目 HTTPS 页面说明来源，并提供实际适用的许可链接。AI 生成必须诚实标记，不得借知名词典或 Word Atlas 的名称冒充已核验内容。name、license、attribution 必须至少包含一个非空白字符，并提供真实、完整的署名和许可。

示例的 source.url 使用真实的生成工具项目首页 `https://openai.com/`；它不是示例托管地址，也不表示该网站刊载或核验了这些释义。示例 attribution 明确说明这一点，示例生成内容以 CC0 1.0 提供：`https://creativecommons.org/publicdomain/zero/1.0/`。这不是宣称 OpenAI 网站整体使用 CC0，也没有赋予外部资料许可。

如使用 Word Atlas 的实际数据或媒体，应先核验 `https://github.com/designfuchen/word-atlas` 中具体资源及其适用许可，再按原要求署名；该链接只可作为实际来自该库的内容来源，不能给 AI 示例背书。未核验 URL、无权限或不存在的媒体一律省略。校验器不访问网络，不能证明 URL 存在、释义正确或许可适用。

## 词条

每条必须包含：

| 字段 | 约束 |
| --- | --- |
| id | 与词表 ID 同样的 ASCII 规则；同一文件内不能重复 |
| term | 非空字符串，最多 300 字符 |
| senses | 至少一项；每项必须有 partOfSpeech、definition、translation 三个字符串；definition 非空，translation 可为空 |
| examples | 数组，可为空；每项必须有 text、translation；text 非空，translation 可为空 |
| level | `""`、`A1`、`A2`、`B1`、`B2`、`C1`、`C2` |
| topic | 非空字符串，最多 100 字符 |

`partOfSpeech` 没有枚举，可为空。非空约束按字符串长度执行，不做自动 trim；创作时仍应避免只有空白的内容。例句无需包含 term 的完全一致字符串，词形变化如 motivates 是合法的。

可选属性：`pronunciations: {uk?: string, us?: string}`；`collocations`、`family`、`synonyms`、`antonyms` 均为字符串数组；`tip`、`note` 为字符串；`media` 可有 `pronunciationURL`、`exampleAudioURL`、`imageURL`。缺失可选数据按空值处理，推荐直接省略，不能写 null；空数组、空对象、普通文本空字符串可用，媒体属性一旦出现则必须有 HTTPS URL。不知道定义时不能用空 definition 或空 senses 占位，应补充可信内容或暂不收录。

## 校验

在项目目录运行，Python 3 标准库即可，无需 pip：

```sh
python3 word-list-kit/validate.py word-list-kit/examples/study-starter.json
python3 word-list-kit/validate.py my-list.json another-list.json
```

成功输出 `OK 路径: N entries`，退出码 0。任一失败时退出码 1，标准错误输出包含 JSON 路径，例如 `$["entries"][0]["senses"][0]["definition"]`。语法、编码、文件大小错误使用根路径 `$`。拒绝重复 JSON 属性、未知字段、错误版本、目标语言、非法 ID、保留 ID、重复词条 ID、缺少释义、超长字段和超大文件。检查只读，不重写输入。

`word-list.schema.json` 是 draft 2020-12，递归对象均为 `additionalProperties: false`。标准库校验器读取这个文件，执行其使用的 `$ref`、allOf、not、const、enum、type、required、properties、additionalProperties、items、min/maxItems、min/maxLength、pattern 断言；它不是通用 JSON Schema 引擎，扩展 Schema 词汇时需同时扩展校验器。

URL 正则要求小写 `https://`、非空主机、可选数字端口，禁止用户凭据、空白、控制字符与反斜杠；不做网络请求或主机存在性检查。Schema 与 CLI 使用同一正则。HTTPS 并不能代替来源核验。

标准 JSON Schema 无法对对象数组按某一属性去重，也不检查原始文件字节数。因此 `x-uniqueBy`、`x-maxFileBytes` 仅为说明性扩展，CLI 显式执行重复 ID 和文件大小检查。JSON 对象重复键也必须在解析时检查，普通 Schema 引擎无法恢复已丢失的重复键。

若环境已经安装 `jsonschema`，可附加检查（不是必需步骤）：

```sh
python3 - <<'PY'
import json
from pathlib import Path
from jsonschema import Draft202012Validator
kit = Path('word-list-kit')
schema = json.loads((kit / 'word-list.schema.json').read_text(encoding='utf-8'))
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(json.loads((kit / 'examples/study-starter.json').read_text(encoding='utf-8')))
print('Schema OK')
PY
```

仍需运行 `validate.py` 检查字节数、ID 重复和导入保留值。

Schema 也用于校验随应用发布的内置词表，因此允许其文档 ID 为 `ielts`；默认 CLI 会额外拒绝此保留 ID，避免生成不可导入文件。仅审计应用自带文件时使用：

```sh
python3 word-list-kit/validate.py --allow-builtin Kotoba/word-atlas.json
```

`--allow-builtin` 只放宽内置 ID 检查，不放宽其他约束，也不代表允许导入或覆盖内置词表。生成供用户导入的文件必须使用默认校验命令，不能用此选项绕过保留 ID。

## 与应用合并的契约

以下是导入器应遵守的语义，不是本工具包已经实现或已核验上线的承诺：预览校验不写入；确认后原子写入合并后的完整文件，无效文件整份拒绝。文件保存在 Application Support/WordLists，而不是用户媒体目录 Files.dir。

已有同 list ID 的重复 entry ID 应由用户选择跳过或更新内容，永远不更改学习排期。文件中缺少的已有词条不会被删除；已有词表的 language、translationLanguage 不得改变；内置 `ielts` 不允许覆盖。导入本身不创建 Cards，之后用户执行 Add Cards 才复制 list ID、entry ID、language 和 definitions，重复卡片不重新排期；旧 Cards 默认 list ID `ielts` 保留。离线 CLI 没有应用数据库，不能检查已有词表的语言或执行任何合并。
