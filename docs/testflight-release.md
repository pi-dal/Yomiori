# Yomiori TestFlight 发布

2026-10-29：用户已授权全局改名并发布 TestFlight，发布操作使用 `asc`。

## 最新发布：1.1.2 (10)，词汇难度渐进与回忆答案优化

2026-11-11：用户授权「发个新版吧，我又加了一些，同时 commit and push」。沿用 `asc-release-flow`、`asc-xcode-build` 和 `asc-testflight-orchestration` 的发布流程，使用已验证的临时钥匙串签名方式。

- 版本 **1.1.2 (10)**：每日新词在最低 CEFR 等级以上逐步提高难度，按词义／搭配数量估算级内常用程度，并参考实际复习表现选择目标；回忆答案采用正文大小、左对齐，每项显示首个词义。
- 完整单元／集成测试和相关 UI 回归共 **103 项通过、1 项真机音频测试跳过、0 项失败**；含新增渐进选词测试及 5 项每日学习 UI 验收。其余 UI 场景沿用 Build 9 已完成的验收。详见[本次验收](acceptance/testflight-10.md)。
- Release arm64 归档及 IPA 导出成功；归档及解包 IPA 严格签名、版本身份、发布权限和隐私清单检查通过。99 个源码／工程／配置文件与构建前快照一致；临时签名钥匙串已删除并恢复原搜索列表。
- Build／Upload／Beta Review ID：`5cf8577f-5797-4bfe-9372-5f7c37042cea`。Apple 回读：`processingState=VALID`、`internalBuildState=IN_BETA_TESTING`、`externalBuildState=WAITING_FOR_BETA_REVIEW`、`betaReviewState=WAITING_FOR_REVIEW`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。
- 外部审核提交时间：2026-11-11 23:37:09 PST。Internal Testers 和 Yomiori Email Testers 两组访问关系完整回读；中英文 What to Test 已写入并确认；TestFlight 严格校验零错误／零警告。
- 产物、测试、签名及 Apple 回执：`/tmp/yomiori-testflight-10/`。IPA SHA-256：`59f8c75568bb3e147426515cff7acf741ffec7337bfc6815fd0c06d44a3a9861`。
- 此次提交包含自 Build 6 以来尚未提交的学习流程、词书、阅读词汇标记、Coach 联动、测试与发布记录；按用户要求提交并推送至 `origin/main`。
- 监控：`asc builds build-beta-detail view --build-id 5cf8577f-5797-4bfe-9372-5f7c37042cea --output table`。

## 历史发布：1.1.1 (9)，复习与阅读／Coach 联动

2026-11-11：用户授权「来发个新版，我更新了一些东西」。使用 `asc-release-flow`、`asc-xcode-build`、`asc-testflight-orchestration` 完成上传及测试组分发，以 `asc-submission-health` 回读 Apple 状态。

- 版本 **1.1.1 (9)**：新词在语境中认识后间隔主动回忆，错词在本轮稍后重现，含学习总结及自由练习；阅读器识别已存词汇及支持的日英词形变化；Coach 优先巩固今日词汇，纠错可保存为复习卡；今日学习与成长里程碑互相衔接。
- 完整测试 **123 项通过、1 项真机音频测试跳过、0 项失败**：94 项单元／集成测试通过，29 项 UI 验收通过。详见[本次验收](acceptance/testflight-9.md)。
- Release arm64 归档及 IPA 导出成功，归档 App 和解包 IPA 严格签名校验、版本身份、发布权限、隐私清单均通过。临时签名钥匙串已删除并恢复原搜索列表。
- Build／Upload／Beta Review ID：`82c66e8d-cda5-44cf-843d-7c86179dad6f`。Apple 回读：`processingState=VALID`、`internalBuildState=IN_BETA_TESTING`、`externalBuildState=WAITING_FOR_BETA_REVIEW`、`betaReviewState=WAITING_FOR_REVIEW`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。
- 外部审核提交时间：2026-11-11 22:30:49 PST。现有 Internal Testers 和 Yomiori Email Testers 两组访问关系已完整回读；中英文 What to Test 已创建并确认。TestFlight 严格校验零错误／零警告。
- 产物、测试结果、签名校验和 Apple 回执：`/tmp/yomiori-testflight-9/`。IPA SHA-256：`bccd717721fda8768b345fba9c3a01242673e371f813badaf8f5d825f3e61d0b`。
- 监控：`asc builds build-beta-detail view --build-id 82c66e8d-cda5-44cf-843d-7c86179dad6f --output table`。此次为 TestFlight 发布；代码保留在工作区。

## 历史发布：1.1 (8)，词书计划与引导式学习

2026-11-09：签名归档和 IPA 上传完成。包含词书详情、学习进度、每日目标、今日学习及自由练习入口，以及引导式单词学习流程。

- Build／Upload／Beta Review ID：`108e2ad8-b857-45da-81aa-44567febd5f0`。Apple 处理状态 `VALID`；2026-11-11 回读确认内部及外部均为 `IN_BETA_TESTING`，自动通知开启。
- 现有 Internal Testers 与 Yomiori Email Testers 两组已获得访问，中英文 What to Test 已写入。
- 归档及解包 IPA 严格签名校验通过；临时签名钥匙串已清理并恢复原搜索列表。
- 产物及日志：`/tmp/yomiori-testflight-8/`。IPA SHA-256：`a404a66018f1283a8f25701149459f4b5a2a5aa1ee1adb8d21b9e9626450282a`。

## 历史发布：1.0 (7)，英语词汇难度分级

2026-11-05：用户授权「发版吧」，并要求继续完成。使用 `asc-release-flow`、`asc-xcode-build`、`asc-testflight-orchestration` 执行本次 TestFlight 发布，使用 `asc-submission-health` 回读 Apple 状态。

- 版本 **1.0 (7)**：英语新词默认 B1 及以上，每日设置可选 A1–C2 或全部等级；词表等级随新卡保存并显示于词表行和复习卡。到期旧卡继续复习，无等级词汇仍可学习；旧卡不会自动回填等级。
- 最终 **77 项单元测试（14 个测试组）通过**，现有 **26 项 UI 验收通过**。新等级选择器的专项视觉验收、build-6 数据库原地迁移尚未执行。参见[英语难度验收](acceptance/word-difficulty.md)。
- Release arm64 归档及 IPA 导出成功，归档和解包 App 严格签名校验通过，两个隐私清单齐全。临时签名钥匙串已删除，原搜索列表恢复。
- Build／Upload／Beta Review ID：`1a944478-1e78-40dd-b81c-d97383006938`。Apple 最终回读：`processingState=VALID`、`betaReviewState=APPROVED`、内部和外部均为 `IN_BETA_TESTING`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。
- 两个现有测试组的完整成员关系已确认，中英文 What to Test 已写入并回读；TestFlight 严格校验零错误／零警告。此次为 TestFlight 发布。
- 监控：`asc builds build-beta-detail view --build-id 1a944478-1e78-40dd-b81c-d97383006938 --output table`。
- 产物、日志、中英文 What to Test：`/tmp/yomiori-testflight-7/`。IPA SHA-256：`90b8ea605bdca60ad1268ede0da27c59e5a4be69f47a9ad9ef3277cc7f3930fe`。

## 历史发布：1.0 (6)，每日学习自动化与按钮统一

2026-11-05：用户授权「c，p，发新版」。使用 `asc-release-flow` 上传、关联现有组并提交 Beta 审核，使用 `asc-submission-health` 回读状态。

- 版本 **1.0 (6)**，包含首页一键今日学习、每天默认 30 张／最多 5 个新词、到期旧卡优先、收藏自动制卡、进度持久化、10 分钟后重学，以及可选每日本地提醒。
- 主操作、纸色次操作、文字／整行入口统一到和纸、墨色、抹茶样式；补齐加载、禁用、危险操作与大字号布局。
- 发布前完整 **75 项单元测试（14 个测试组）通过**；按钮最终 **6 项界面场景通过**，另有每日学习专项及实际深色模式复测。参见[每日学习验收](acceptance/daily-study.md)、[按钮验收](acceptance/button-refinement.md)。测试结束时 Simulator 诊断收集出现 `simctl` 路径警告，测试结果为 `TEST SUCCEEDED`。
- Release arm64 归档和 IPA 导出成功，归档及解包 App 严格签名校验通过；隐私清单和权限说明齐全。临时签名钥匙串已删除，搜索列表恢复。
- Build／Upload／Beta Review ID：`7fca9433-7dd2-4bb2-af6d-8eed8ad6b7f8`。Apple 回读：`processingState=VALID`、`betaReviewState=APPROVED`、内部和外部均为 `IN_BETA_TESTING`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。
- 两个现有测试组成员关系完整确认，中英文 What to Test 已创建并回读；严格 TestFlight 校验零错误／零警告。
- 提醒需要首次授权，打开 App 时补齐未来 30 天排程；日语新词需要收藏或导入词库。真机通知送达／点击、实时语音服务、横屏视觉验收及完整 VoiceOver 尚未确认；测试说明已披露相关设置和边界。
- 产物与 Apple 回读：`/tmp/yomiori-testflight-6/`。IPA SHA-256：`b8f1707556c75bb5c87ef8cbf229a9089de2c40b1a262f1c2e070d9a5f9d2fc7`。
- 监控：`asc builds build-beta-detail view --build-id 7fca9433-7dd2-4bb2-af6d-8eed8ad6b7f8 --output table`。此次为 TestFlight 发布。

## 历史发布：1.0 (5)，稳定性修复与查词／实时语音

2026-11-03：用户授权「发个版」。使用 `asc-release-flow` 发布至现有 TestFlight 测试组。

- 版本 **1.0 (5)**，签名归档及 IPA 导出成功，严格签名校验通过；麦克风／语音识别权限说明和两个隐私清单齐全。
- 修复异常字幕时间导致整数转换崩溃、重复字幕 ID、播放器重复载入的观察者泄漏、PDF 同步回写 SwiftUI 状态、复习间隔越界及学习时长输入；不重置词库或数据库。
- 同时包含 `cb9413e` 的快速查词／收藏与实验性实时语音 Coach。实时语音仍缺真机及有效 Qwen Key 的端到端验收，中英文测试说明和审核备注均披露该限制。
- 发布前最终 **66 项自动化测试通过、1 项真机音频测试跳过**；8 项不同 UI 回归通过，PDF 生命周期修复后专项复测全部通过。见[崩溃排查验收](acceptance/crash-triage.md)。
- 产物、签名清单、上传与 Apple 状态回读：`/tmp/yomiori-testflight-5/`。
- IPA SHA-256：`2e19d4b124341a0710962650534a920c4833951ccd79c260adbbe3c88eb27eba`。
- Build／Upload／Beta Review ID：`d4e2c648-2b3f-4c25-b318-8e4f78a2458d`。Apple 回读：`processingState=VALID`、`betaReviewState=APPROVED`、内部和外部均为 `IN_BETA_TESTING`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。
- 现有 `Internal Testers` 和 `Yomiori Email Testers` 两组成员关系完整确认；中英文 What to Test 已写入并回读，TestFlight 严格校验零错误／零警告。未创建新测试组或公开链接，未提交正式 App Store 版本。
- 临时签名钥匙串已删除并恢复原搜索列表。监控：`asc builds build-beta-detail view --build-id d4e2c648-2b3f-4c25-b318-8e4f78a2458d --output table`。

## 历史发布：1.0 (4)，和纸墨色与双语阅读

2026-11-03：用户授权「再发个版，我更新了一些，顺便 commit and push」。使用 `asc-release-flow` 上传、分发和提交 Beta 审核，使用 `asc-submission-health` 回读状态。

- 版本 **1.0 (4)**；Build / Upload / Beta Review ID：`af7ae4fc-fa5a-465e-87ef-bad2ebf155b4`。
- Apple 最终回读：`processingState=VALID`、`betaReviewState=APPROVED`、内部和外部 `IN_BETA_TESTING`、`autoNotifyEnabled=true`、`usesNonExemptEncryption=false`。现有内部组保留全部构建访问权限，外部邮件测试组已显式关联；未创建新组。
- 包含和纸／墨色／抹茶配色、明朝体与衬线阅读字体、中文界面字体回退、阅读切行动效、音视频句内进度，以及关闭／点按显示／始终显示三种译文模式；同时包含此前未提交的书库查找和原生 PDF 阅读功能。
- 中英文 What to Test 均已写入并回读。发布前 **54 项单元测试 + 8 项界面／PDF 测试全部通过**，含两项实际深色模式复测。新增译文揭示／再次隐藏／切行重置的 UI 回归测试。
- 正式 Release arm64 归档、导出、归档 app 和解包 IPA 严格签名校验通过，两个隐私清单齐全；临时签名钥匙串已清理，原搜索列表已恢复。
- 产物及 Apple 回读：`/tmp/yomiori-testflight-4/`。IPA SHA-256：`fae955272a1b6ea18a24d23b12ca2130489f739b205f754b7ae9aaebdc85887f`。
- 监控：`asc builds build-beta-detail view --build-id af7ae4fc-fa5a-465e-87ef-bad2ebf155b4 --output table`。
- 验证范围与截图：[1.0 (4) 验收](acceptance/testflight-4.md)。此次为 TestFlight 发布，未提交正式 App Store 版本。

## 历史发布：1.0 (3)，内容书库与阅读恢复修复

2026-11-01：用户授权「那现在发个版」，使用 `asc-release-flow` 执行本次 TestFlight 发布，并按 `asc-submission-health` 回读审核状态。

- 版本 **1.0 (3)**；Build / Upload / Beta Review ID：`dbdff6d8-f98c-40f2-a42f-c7355869f837`。
- Apple 最终回读：`processingState = VALID`、`internalBuildState = IN_BETA_TESTING`、`externalBuildState = IN_BETA_TESTING`、`betaReviewState = APPROVED`、`autoNotifyEnabled = true`、`usesNonExemptEncryption = false`。
- 两个现有组的完整成员关系已回读：`Internal Testers` 有全部构建访问权限，`Yomiori Email Testers` 已显式关联。内部组不接受显式 add 请求（HTTP 422）；保留其自动访问配置，外部组单独关联并提交审核成功。
- `en-US` 和 `zh-Hans` What to Test 已创建并回读确认；涵盖内容优先的新书库、标题搜索/排序、纯文本行导航、PDF 恢复位置和来源跳转修复。未创建新测试组，未更改公开链接配置。
- 发布前完整单元测试 **54/54，12 个测试组通过**：`/tmp/yomiori-testflight-3/UnitTests.xcresult`。此前界面/PDF 验证见 [阅读恢复验收](acceptance/reading-verification.md)、[书库查找验收](acceptance/library-discovery.md)。
- 正式 arm64 Release 归档及导出成功；归档 app 与解包 IPA 均通过 `codesign --verify --deep --strict`，application-identifier 为 `6Y2YB464VU.com.pidal.yomiori`，get-task-allow=false，含两个隐私清单。临时签名钥匙串已清理，搜索列表恢复。
- 归档：`/tmp/yomiori-testflight-3/Yomiori.xcarchive`；IPA：`/tmp/yomiori-testflight-3/export/Yomiori.ipa`。
- IPA SHA-256：`256a43321317982fbc4e1a3f3b390ef8a6f7c92fb1e0f9e05f3cf3fdbe2cd4c3`。
- 发布日志、测试说明、签名清单及 Apple 回读 JSON 保存在 `/tmp/yomiori-testflight-3/`。上传先执行 dry run；群组分配先预览；外部审核使用 `--submit --confirm`。
- 监控：`asc builds build-beta-detail view --build-id dbdff6d8-f98c-40f2-a42f-c7355869f837 --output table`。
- 此次为 TestFlight 发布，未提交正式 App Store 版本。代码改动保留在当前工作区，未自动创建 Git 提交。

## 历史发布：1.0 (2)，Liquid Glass 与新图标

2026-10-29：用户授权「发个版」，沿用现有 TestFlight 配置发布本次界面改动。

- 版本 **1.0 (2)**；Build / Upload ID：`50c1b165-669a-4195-bd59-7f3b956cb429`。
- Apple 回读：`processingState = VALID`、`internalBuildState = IN_BETA_TESTING`、`usesNonExemptEncryption = false`。
- 两个现有测试组均已关联，内部组拥有全部构建访问权限；外部组保留邮件测试配置和关闭公开链接。
- 新版外部送审最初被旧构建 1 的待审记录阻挡。通过 App Store Connect 的 **Remove from Review** 撤回构建 1 的旧审核，再使用 `asc testflight review submit` 成功提交构建 2。
- 新审核提交时间：**2026-10-29 15:37:48 UTC**；`betaReviewState = WAITING_FOR_REVIEW`，`externalBuildState = WAITING_FOR_BETA_REVIEW`。`autoNotifyEnabled = true`。
- `en-US` 与 `zh-Hans` What to Test 已更新并回读确认，重点为 Liquid Glass、浅深色模式、大字号、输入键盘和原有学习／导出流程。
- 签名归档：`/tmp/yomiori-testflight-2/Yomiori.xcarchive`；IPA：`/tmp/yomiori-testflight-2/export/Yomiori.ipa`。
- IPA SHA-256：`21a4a0858bdfcfd9695016ba19bf4ef672e18aedd3a724ce93b5b4885443cbfe`。
- 签名严格验证、arm64 Release archive / export 成功；构建及上传日志在 `/tmp/yomiori-testflight-2/`，临时签名钥匙串已清理并恢复原搜索列表。
- 本次界面验收：48 项单元／集成测试 + 7 项 UI 测试通过，后续专项复测通过，详见 [Liquid Glass 验收](acceptance/liquid-glass.md)。

下面记录为构建 1 的历史发布详情，其待审记录已被本次新版审核替代。

## 应用身份

- 名称：**Yomiori（よみおり）**，取「読み」（阅读）与「織り」（编织）意象的自造品牌名。
- App Store Connect ID：`6828409958`
- Bundle ID：`com.pidal.yomiori`，Developer 资源 ID `98GK9S6387`
- SKU：`YOMIORI-IOS-001`，主要语言 `en-US`
- 版本/构建：`1.0 (1)`，最低 iOS 26.0
- Team：`6Y2YB464VU`
- [App Store Connect / TestFlight](https://appstoreconnect.apple.com/apps/6828409958/testflight/ios)

原名 Kotoba 被其他 Apple 账号占用。用户授权重新命名后，Yomiori 应用记录已创建成功。桌面名称、源文件、工程、共享 scheme、模块及测试 target、权限文案、导出文件、工具包和当前文档已同步。GitHub 仓库已更名为 [`pi-dal/Yomiori`](https://github.com/pi-dal/Yomiori)，本地 origin 和工作区目录同步为 Yomiori；历史验收产物保留原路径。v1 文件格式标识 `kotoba.wordlist` 保持稳定，旧词表继续兼容。

## 签名与产物

- Distribution 证书：`58X6AM89VY`
- Profile：`Yomiori App Store com.pidal.yomiori 20261029`，资源 ID `A8WJXVA32X`，UUID `08d4a069-7625-43a6-8e10-61e6dd6a0ca2`
- 导出配置：`Config/ExportOptions-TestFlight.plist`
- 签名归档：`/tmp/yomiori-testflight/Yomiori.xcarchive`
- IPA：`/tmp/yomiori-testflight/export/Yomiori.ipa`
- IPA SHA-256：`045a4220d5032edde4f28995b6192cce0807047dc308cada97fff55ce743f42c`
- 归档/导出日志：`/tmp/yomiori-testflight/build.log`
- 上传日志：`/tmp/yomiori-testflight/upload.log`

签名严格验证通过，application-identifier 为 `6Y2YB464VU.com.pidal.yomiori`，get-task-allow=false。隐私清单已包含在归档中：UserDefaults CA92.1、SystemBootTime 35F9.1；ZIPFoundation 自带相关清单。隐私清单不代替 App Store 隐私问卷。

本机登录钥匙串非交互签名曾报 errSecInternalComponent；归档采用临时签名钥匙串，退出后恢复原搜索列表，不修改现有钥匙串 ACL。包装脚本位于 `/tmp/yomiori-testflight/sign-release.py`、`build-release.py`。原名的未发布签名资源及旧 IPA 保留但不用于此次上传。

后续发版沿用成功的 `/tmp/yomiori-testflight-8/release-build.py` 流程：从 `~/.asc/keys/open-screen-sharing-distribution/distribution.key` 和 `distribution.cer` 导入临时钥匙串，分区权限为 `apple-tool:,apple:,codesign:`，使用 `Config/ExportOptions-TestFlight.plist` 导出，在 `finally` 恢复搜索列表并删除临时钥匙串。普通发版无需导出 login 私钥、调整系统证书信任或撤销 Distribution 证书。签名流程及排障教训已保存至 nmem 记忆 `93948758-c0cd-4b49-8f15-4b179cb8b4d1`。

## 验证

改名后重新执行完整测试，**48 项单元/集成测试 + 4 项标准 Simulator UI 测试全部通过**，iPhone arm64 Release 归档及导出成功。UI 覆盖 Markdown/流式、阅读器点词和原生选区、设置许可证入口，以及系统分享取消和保存文件后的导出状态。

- XCTest 结果：`/tmp/yomiori-testflight/Acceptance.xcresult`
- 测试日志：`/tmp/yomiori-testflight/tests.log`
- 工具包示例和 7,298 条内置词表验证通过。
- `git diff --check` 通过。
- 仍未覆盖真机和 Anki 接收端；见[原 package 验收记录](acceptance/2026-10-29.md)。

## TestFlight 状态

**已发布到内部 TestFlight，Apple 处理通过。** 通过 `asc builds upload --wait` 上传，并用独立读取确认：

- Build ID / Upload ID：`8ae00f94-c775-407e-9d78-cc1d6b21d868`
- `processingState = VALID`
- `internalBuildState = IN_BETA_TESTING`
- `usesNonExemptEncryption = false`，未过期，Apple 返回过期时间为 2027-01-27。
- 内部群组 `Internal Testers`（`6cd8a33b-ba49-4c0c-8b5e-c5b44d041344`）已包含该构建，允许访问所有构建。关系读取完整。
- Account Holder 已作为内部测试者加入，状态 `INVITED`；Apple 已自动发出邀请。
- `en-US` 和 `zh-Hans` 的 Beta 应用说明及 What to Test 均已写入并回读确认。
- 按用户要求对齐 Sakamoto 的测试人员配置，已创建外部邮件组 `Yomiori Email Testers`（`bd75a1a1-ac32-40a9-97ba-1c45cae1a6dd`），加入 Sakamoto 邮件组的同一位测试者，并分配本构建。公开链接关闭，反馈开启；个人邮箱不写入仓库。
- 外部 Beta App Review 已于 2026-10-29 12:18:35 UTC 提交，submission ID `8ae00f94-c775-407e-9d78-cc1d6b21d868`。回读 `betaReviewState = WAITING_FOR_REVIEW`、`externalBuildState = WAITING_FOR_BETA_REVIEW`；内部仍为 `IN_BETA_TESTING`。
- 审核联系人沿用 Sakamoto 的既有资料并回读核对；中英文反馈邮箱已补齐，审核备注说明本地功能无需登录、AI 服务由测试者自行配置。
- 邮件组测试者 ID `ffd93afb-16aa-4d3d-83bb-0725cc94a59c`，状态 `NOT_INVITED`；需要先通过 Apple 外部 Beta 审核，再执行已授权的邀请并核对状态。未创建定时监控。

本机会话仍绑定改名前的工作目录，已保留 `Developer/Kotoba → Developer/Yomiori` 兼容符号链接；实际项目目录和 GitHub 仓库均为 Yomiori。

测试说明涵盖阅读/PDF、词表导入和复习；Coach Markdown 与流式；阅读器点词、选区及振假名；导出 CSV/音频 ZIP，取消分享不标记、完成分享后标记。AI 功能需测试者自行配置 HTTPS Responses/Chat Completions 服务、模型及 API key。
