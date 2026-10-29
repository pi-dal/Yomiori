# FlowDown package 可复用性评估

审查日期：2026-10-29。针对 Yomiori 当前 SwiftUI / SwiftData、AI 配置、Coach、振假名阅读器和 CSV/音频导出实现评估。

**已接入 MarkdownView 4.8.4、ZIPFoundation 0.9.20 和 Litext 3.6.5。** Coach 使用 Markdown 和流式渲染，导出生成一个 CSV/音频 ZIP，普通阅读文本使用 Litext 原生选区。日语振假名保留现有 CoreText 排版：兼容测试发现 Litext 在部分宽度与字号下会拆开带读音的词，尚不满足完全替换条件。其余包按具体功能需要采用。

## 依据与版本

以 FlowDown 的 [ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32](https://github.com/Lakr233/FlowDown/tree/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32) 为准，直接读取其 [project.pbxproj](https://github.com/Lakr233/FlowDown/blob/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32/FlowDown.xcodeproj/project.pbxproj)、[Package.resolved](https://github.com/Lakr233/FlowDown/blob/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32/FlowDown.xcworkspace/xcshareddata/swiftpm/Package.resolved) 和候选库在锁定 revision 的 manifest、LICENSE、README、关键源码。

搜索索引中的 `Frameworks/RunestoneEditor` 是旧目录。该提交实际通过远程 `Runestone.xcframework` 提供 `RunestoneEditor` 产品。`LanguageModelChatUI` 虽在 README 中列为提取库，但不在此提交的锁定依赖清单；另行检查了它的 main 提交 `e7bfb39f42804e1fd8b6fb22fa64ee987f5a9fa4`。

Yomiori 部署目标为 iOS 26。新增三个直接依赖使用精确版本要求，并提交 Package.resolved 锁定传递依赖。包需要 Swift 6.2 工具链；本机使用 Xcode 27 验证，App 仍使用 Swift 5 语言模式。

## 优先候选

| Package / FlowDown 锁定版本 | 在 Yomiori 的用途 | 成本与限制 | 建议 |
| --- | --- | --- | --- |
| [MarkdownView 4.8.4](https://github.com/Lakr233/MarkdownView/tree/49bbbffe46cd502b254a88f87eff90b15fcb82b7) | Coach 回答的 Markdown、列表、表格和流式输出。当前 `CoachView.Bubble` 逐行拼接 SwiftUI Text，不解释 Markdown。 | MIT。提供 SwiftUI `MarkdownView(text).streaming(isGenerating)`。渲染产品依赖 Litext/LitextAnimation、SwiftMath、collections、cmark 和 LRUCache；并非只有一个小文件。为移动显示简化了部分 CommonMark 语义。 | **优先试接**，只包在助手回复渲染组件中，保留原始消息和用户消息。 |
| [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/tree/22787ffb59de99e5dc1fbfe80b19c97a904ad48d) | 把当前 Anki 导出的 `cards.csv` 和音频合为一个分享文件；以后也可用于备份包。 | MIT；Apple 平台无需其他第三方包，支持 Progress 取消。ZIP 本身不等于 Anki `.apkg`，不能仅换后缀；后者还涉及 Anki 数据库和媒体格式。 | **优先试接**，边界放在导出服务，继续遵守分享完成后才标记 exported 的规则。 |
| [Litext 3.6.5](https://github.com/Lakr233/Litext/tree/684b4a911be9d0b07ddd0303d22a72f6ae522a03) | 阅读器的 CoreText 布局、选择手柄、放大镜、点击定位和菜单；Coach 也可经 MarkdownView 间接使用。 | MIT。核心 Litext target 无外部 target 依赖，动画产品才使用 DisplayLink；包解析仍会看到 DisplayLink。公开字符定位、选区、选区变化和自定义菜单接口。未验证 Yomiori 特有的 CTRubyAnnotation、词边界换行和命中区域。 | **先做原型再替换**，保留 `TappableText` 接口，验证日语振假名和点词。 |
| [SwiftSoup 2.14.2](https://github.com/scinfu/SwiftSoup/tree/7a185638b31911a9980655b70a26af1279d4917b) | 新增网页文章导入时解析 HTML，提取标题、段落和链接。 | MIT；manifest 无第三方依赖。它是 HTML parser，并不自动保证提取到文章正文，也不执行动态页面 JavaScript。FlowDown 通过 ScrubberKit 使用它。 | **静态网页导入的首选候选**；当前仅媒体/RSS 的链接导入无需先引入。 |
| [ScrubberKit 0.2.0](https://github.com/Lakr233/ScrubberKit/tree/b69932dc44461dd4a73aafeb78d514222f68d3e1) | 动态网页内容提取、HTML 转 Markdown，后续也可支持联网检索。 | MIT；依赖 SwiftSoup，包含 WebKit worker 和 JS 资源。`Scrubber.document(for:completion:)` 可直接抓取一个 URL，无需发起搜索。该静态入口不返回取消句柄；实例 `run` 的搜索路径有 cancel，不能混为一谈。最终文本是页面清洗结果，未保证文章正文准确性。 | **按功能采用**；动态页面确有需求时再加，并用操作身份拒绝取消后的回调。 |
| [ListViewKit 4.6.0](https://github.com/Lakr233/ListViewKit/tree/2d9273cd108a4c5a1d9fd227bfb5916f551bb0cc) | 很长的 Coach 消息列表、流式单行更新、加载历史时保持滚动位置。 | MIT；依赖 DisplayLink。UIKit/AppKit 列表，Yomiori 需要 UIViewRepresentable 和自己的 row 适配；`append`/`update` 能局部更新，但整数组 `apply` 仍为 O(n)。 | **先测量再采用**；优先收紧 SwiftData 查询与分页，列表虚拟化不能解决全量数据库读取。 |

### MarkdownView 的接入边界

- 使用一个 `CoachMessageContent` 适配器承接普通/流式状态，CoachSession 和持久化数据继续保留原始文本。
- 用户输入按普通文本显示，避免用户的字面符号被当作格式。
- 适配现有 Theme、Dynamic Type、深浅色；保留初级阶段括号译文的次要颜色。MarkdownView 不会自动实现 Yomiori 的这种语义样式。
- 验证半个强调符号、未闭合链接、表格、长代码块和结束后的最终渲染；核对复制文本和系统辅助功能。
- MarkdownParser 是独立 product，其 target 只依赖 cmark；仅需要文本分析时可只链接 parser。不过包级依赖仍可能参加解析，不应宣称完全不拉取 Litext/SwiftMath。
- 若只需要加粗和链接，先评估系统 AttributedString 的内联 Markdown；只有实际需要块级结构和流式布局时，完整 renderer 的成本才值得。

### Litext 原型的通过标准

现有 `ReaderTextView.swift` 除了通用选区代码，还有日语业务规则。仅确认 Litext 支持 NSAttributedString/CoreText 不足以证明可以无损替换。至少检查：

1. 带 CTRubyAnnotation 的长词在窄屏和大字号下布局正确，词中换行符合现有要求。
2. 振假名、正文、标点、中英日混排、emoji 附近的字符索引和点词范围一致。
3. 复制、选择手柄、查词、挖卡和自定义菜单都使用正确的 UTF-16 范围。
4. 显示高亮和选区时的矩形与文字一致；VoiceOver 可读，菜单可以关闭和再次打开。

它适合减少通用绘制/交互维护，但分词、读音生成和学习业务动作仍需 Yomiori 自己管理。

## 能用，但当前收益有限

| Package | 评估 |
| --- | --- |
| [ConfigurableKit 4.2.0](https://github.com/Lakr233/ConfigurableKit/tree/e0cfe2c5b75b1d8cf60255433c9e50be52b484c0) | MIT；依赖 OrderedCollections。数据驱动设置、Codable 值和可替换 KeyValueStorage 有价值，UI 以 UIKit/AppKit 为主。当前 SwiftUI Form + AppStorage 已覆盖少量设置。其 `KeyValueStorage.setValue` 不 throws，不能自然承接现有 Keychain 失败的提交语义；迁移时仍需独立的凭据服务与草稿保存。以后配置项和嵌套模型管理显著增长时再考虑。README 的旧平台要求低于当前 manifest，本文以 manifest 为准。 |
| [AlertController 3.0.0](https://github.com/Lakr233/AlertController/tree/02806b7fb8424a609ddad9b5a60bb235c63e92cd) | MIT，manifest 无第三方依赖，提供跨 UIKit/AppKit 的输入、进度和动作弹窗。当前 SwiftUI alert/confirmationDialog/ProgressView 足够；它能减少定制弹窗工作，但不会代替任务状态、取消或失败恢复。 |
| [LRUCache 1.3.0](https://github.com/nicklockwood/LRUCache/tree/f0570e943ea4445d258113ba73f50cb2b7e564ac) | README 标注 MIT，manifest 无依赖。可用于未来多文档排版/分词结果的有界内存缓存；当前单字幕快照无需先换。它不管理磁盘音频缓存过期，也不替代翻译缓存身份。MarkdownView 已直接使用该包。 |
| [EventSource 1.5.1](https://github.com/mattt/EventSource/tree/86b5096ac59ab46e66bd1f6377c604bc1dab0bc2) | 可复用 SSE 标准字段、BOM 和 AsyncSequence；许可证为 MIT 文本。使用 URLSession bytes 的 `.events` 或 parser 时应保留 AIClient 的 HTTP 和终止事件校验，不使用自动重连来重发计费生成请求。AsyncHTTPClient/NIO 是可选 trait 的 target 依赖，manifest 仍声明相应 package。检查到的 parser 没有单事件字节上限；它的 `maximumFinalizationEventCount` 限制的是结束时事件个数，不能代替 Yomiori 的 1 MiB 防护。当前没有直接替换必要。 |
| [Digger 0.1.0](https://github.com/Lakr233/Digger/tree/6bd5c7dfb07b0be8635241fe60508636de83cd43) | MIT，无第三方依赖，适合暂停/继续、进度速度、缓存和并发下载。当前 async URLSession 足够。该版本恢复下载遇到服务器忽略 Range、返回 200 时会报错并移除临时文件，而不是自动从头重下；媒体/RSS 来源不保证都支持 Range。采用前需明确取消、缓存和不支持续传时的策略。 |
| [FlowDownModelExchange](https://github.com/Lakr233/FlowDown/tree/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32/Frameworks/FlowDownModelExchange) | Foundation/CryptoKit，无第三方包，提供 FlowDown URL 握手、签名和加密模型交换。适合明确要“从已安装 FlowDown 导入模型”的功能；不是通用 `.fdmodel` 文件导入器。Yomiori 还需注册回调 scheme、持有会话与密钥、校验回调及映射配置，尤其不能仅凭 URL resolve 认定可信。包内未找到独立许可证，不把它当作独立 MIT 库。 |
| [Logger](https://github.com/Lakr233/FlowDown/tree/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32/Frameworks/Logger) | 无第三方依赖，在 OSLog 外增加文件轮转、尾部读取和清除。当前实现带有 FlowDown.log 名称/目录语义，文件消息为普通 String，不自动继承 OSLog 的隐私脱敏。只有增加本地诊断导出时才有明显收益；届时也需纳入数据清除范围。包内未找到独立许可证。 |

## 当前不建议整体引入

- **[ChatClientKit](https://github.com/Lakr233/ChatClientKit)**：前一轮已评估，借鉴其 Responses/Chat Completions 的分工。当前包也包含 MLX、tokenizer 等本机模型依赖；Yomiori 现阶段的远程文本 complete/stream 已有协议与取消测试。若以后需要多模态或本机模型，再评估整体采用，当前不只为远程请求引入完整运行时。
- **[Storage](https://github.com/Lakr233/FlowDown/tree/ccd38d4c9fb7e64d3ea2f91d836ec7a13ae51b32/Frameworks/Storage)**：WCDB、MarkdownParser、collections、ZIPFoundation、相邻 Logger，并绑定 Conversation/Message/CloudModel/Attachment 等表、版本迁移及 CloudKit 上传队列。它不是可直接接到 SwiftData 实体上的通用仓储或通用 CloudKit 同步引擎。可借鉴逐版本迁移和同步测试思路，不能通过引入它自动补齐 Yomiori 的历史 schema 迁移。
- **[LanguageModelChatUI](https://github.com/Lakr233/LanguageModelChatUI/tree/e7bfb39f42804e1fd8b6fb22fa64ee987f5a9fa4)**：MIT，完整 UIKit 聊天 UI，有 storage/session 扩展点，适合新建通用聊天 App。当前 manifest 还维护自己的 ChatClientKit/ServerEvent targets，依赖 MarkdownView 3.x、Litext 1.x、ListViewKit 1.x，与当前 FlowDown 锁定的 4.x/3.x/4.x 不是同一代。整体接入需要适配 Yomiori 的语言、纠错、学习上下文和现有会话；同工程再引入新版相关库还可能产生版本或同名模块冲突。本文未对旧客户端宣称 Responses 兼容。
- **[Runestone.xcframework 0.3.2](https://github.com/Lakr233/Runestone.xcframework/tree/90576ae5769b1e0ba49b8616cf2de045a8dc36af)**：MIT wrapper，附上游版权说明；二进制 Runestone 和源码适配层提供代码编辑、语法和主题。适合 JSON/提示词源码编辑器；普通模型地址、设置和学习阅读没有足够收益。
- **GlyphixTextFx / ColorfulX / UIEffectKit / Respring 等视觉库**：流式动画、背景和过渡属于可选表现层，不解决当前持久化/取消边界。若使用 MarkdownView，其 LitextAnimation 已提供流式文本动画，无需为相同效果再叠另一套动画库。
- **MCP Swift SDK / iCalendarParser / GPTEncoder / MLX**：分别对应工具协议、日历、模型相关 tokenizer 和本机推理。当前学习功能未提出这些需求；GPTEncoder 的计数也不能视为任意 Responses 模型的精确 token 计数。

## 推荐采用顺序

1. **MarkdownView → Coach 助手回复**：改动限制在渲染适配器，保留会话与存储边界，先验证流式/结束/复制/初级译文样式。
2. **ZIPFoundation → 单文件导出**：导出服务生成 CSV+音频 ZIP，增加解包内容、取消及失败后清理验证；不把 ZIP 声称为 `.apkg`。
3. **Litext → 阅读器原型**：通过振假名与点词测试后，才替换通用选区实现。
4. **SwiftSoup / ScrubberKit → 网页文章导入**：作为新功能单独安排，保留原链接、语言和正文快照；静态 HTML 优先走更小的 parser 路径。
5. **ListViewKit → 大历史列表**：有分页和性能测量后再采用。

## 本轮落地

- `CoachMessageContent.swift`：使用 MarkdownView 渲染助手回复；标题、表格、列表、引用、代码块及复制保留 Markdown 语义。流式更新沿用同一个渲染组件，遵守减少动态效果设置，初级阶段括号译文继续使用次要颜色，代码围栏中的括号不误判为译文。
- `AnkiExporter.swift` / `ExportSheet.swift`：后台生成单个 `Yomiori-Anki.zip`，包含 `cards.csv`、去重音频和中英文导入说明；支持取消和失败清理。用户完成系统分享后才标记已导出。ZIP 不等同于 `.apkg`，接收端需解压并导入。
- `TappableText.swift`：普通文本走 Litext，提供系统选择手柄、放大镜和查词菜单。日语振假名走 `RubyReaderTextView.swift`，保持词边界换行和原有选择行为；两条路径共用 `ReaderTextContent` 的分词、读音和高亮构造，不改变原始 UTF-16 偏移。
- `OpenSourceLicensesView.swift` / `ThirdPartyNotices.txt`：在设置的「Credits / 署名」页提供开源许可证入口，包含直接、传递依赖及上游字体许可文本。
- 修正工程原先覆盖构建产物目录的设置，使 App 和 Swift Package 使用一致的 DerivedData 路径；测试 bundle 使用宿主链接，避免重复链接 Litext。
- Debug 构建可用 `--component-preview` 打开内存中的组件预览，验证 Markdown、流式、振假名开关及导出，不向学习资料库插入样例卡片。

新增自动化覆盖 Markdown 片段身份、代码围栏、UTF-16/emoji 点词、普通文本多字号多宽度布局、振假名词边界、选区更新及菜单、ZIP 解包内容、取消和无效路径清理。模拟器构建与测试结果见 [架构报告](architecture-review.md)。SimRun 已检查 Coach 浅/深色与窄屏排版、流式开始/取消、普通文本点词/长按/查词菜单和导出生成。随后使用标准 iOS Simulator 验收：48 项单元/集成测试及 4 项 UI 测试通过，系统分享取消不标记，Save to Files 完成后标记已导出，并独立解包核对实际交付 ZIP。标准 Simulator 未复现 SimRun 的 FrontBoard 退出；Anki 接收应用尚未安装，接收端与真机验收仍保留。见 [验收证据](acceptance/2026-10-29.md)。

## 许可证与来源边界

FlowDown 主仓库为 AGPL-3.0，README 列出的独立库各有许可证。独立 MIT 仓库可以按其许可证接入并保留版权声明；主仓库内部 package 没有独立 MIT 许可时，不能因它是 Swift package 就按 MIT 使用。上表已区别这两种来源，Storage、Logger、FlowDownModelExchange 不归入可直接按 MIT 接入的清单。

GitHub 源码链接、锁定 revision 和 LICENSE 是本次评估的依据。未对候选测量编译时间、安装包大小、运行时性能，也未替上游执行全套测试，因此不把“上游 README 宣称快”当作 Yomiori 已验证的性能结论。
