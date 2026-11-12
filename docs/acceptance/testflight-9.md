# Yomiori 1.1.1 (9) 发布验收

2026-11-11，iPhone 18 Pro / iOS 27.0 Simulator，Xcode 27.0.0。

## 自动化验证

- 完整 `xcodebuild test`：124 项，123 项通过、1 项跳过、0 项失败。
- 单元／集成测试：94 项通过，1 项仅支持真机的音频引擎测试 `nativeVoiceEngineStartsPlaysAndCloses` 跳过；共 16 个测试组。
- UI 验收：29 项全部通过，涵盖每日引导学习、错词回练、自由练习不改变计划、学习路线、阅读词汇标记、点词／原生选区、译文显示与切句重置、中文大字号、深色模式、书库搜索与删除、阅读／PDF 进度恢复、导入导出、Coach 与语音配置入口。
- 新增 ReviewFlowTests 与 StudyLinksTests 验证复习队列的重现间隔和次数上限、首次失败只记一次 lapse、复习卡去重、词义选项的语言隔离、来源回跳、日英词形识别、Coach 今日词汇优先级、纠错存卡去重和跨日成长统计。
- `Localizable.xcstrings` JSON 解析和 `git diff --check` 通过。
- 结果包：`/tmp/yomiori-testflight-9/Tests.xcresult`，摘要 `test-summary.json`，日志 `tests.log`。

## 发布产物

- 正式 Release arm64 归档及 IPA 导出成功，版本号 `1.1.1`、构建号 `9`。
- 归档 App 和 IPA 解包 App 均通过 `codesign --verify --deep --strict`。
- Bundle ID `com.pidal.yomiori`；Team `6Y2YB464VU`；`application-identifier=6Y2YB464VU.com.pidal.yomiori`；`get-task-allow=false`。
- IPA 中的应用及依赖隐私清单已确认。
- IPA：`/tmp/yomiori-testflight-9/Yomiori.ipa`，19,191,649 字节。
- SHA-256：`bccd717721fda8768b345fba9c3a01242673e371f813badaf8f5d825f3e61d0b`。
- 从已有发布私钥／证书创建临时签名钥匙串；归档及导出后已删除，原钥匙串搜索列表已恢复。
- 发布前对 98 个源码／工程／配置文件的 SHA-256 快照逐一核对，测试与打包期间源码未发生变化；快照为 `source-snapshot.json`。

## 验证边界

真机音频引擎、通知实际送达、配置真实 AI 服务后的对话／实时语音不在模拟器验证范围。测试结果包含既有音频测试的主线程同步调用运行时警告。中英文 What to Test 说明了真机和服务配置要求。

Apple 上传、测试组及审核回读见 [TestFlight 发布记录](../testflight-release.md)。
