# Yomiori TestFlight 发布

2026-10-29：用户已授权全局改名并发布 TestFlight，发布操作使用 `asc`。

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
- 外部状态 `READY_FOR_BETA_SUBMISSION`：尚未提交外部 Beta App Review，也没有公开测试链接。

测试说明涵盖阅读/PDF、词表导入和复习；Coach Markdown 与流式；阅读器点词、选区及振假名；导出 CSV/音频 ZIP，取消分享不标记、完成分享后标记。AI 功能需测试者自行配置 HTTPS Responses/Chat Completions 服务、模型及 API key。
