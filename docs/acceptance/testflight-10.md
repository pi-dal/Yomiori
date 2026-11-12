# Yomiori 1.1.2 (10) 发布验收

2026-11-11，iPhone 18 Pro / iOS 27.0 Simulator，Xcode 27.0.0。

## 本次变化与验证范围

相对已发布 Build 9，应用新增 `WordProgression.swift`，并修改 `DailyStudy.swift`、`ReviewView.swift` 和 `Theme.swift`：每日新词按 CEFR 内连续难度排序，使用复习表现调整选词目标，保留最低等级限制；回忆答案使用正文大小和左对齐排版，每项显示首个词义。

- 完整单元／集成测试：98 项通过，1 项仅支持真机的音频测试 `nativeVoiceEngineStartsPlaysAndCloses` 跳过；共 17 个测试组。
- 本次 5 项 DailyStudyAcceptanceTests 全部通过，涵盖中文大字号、今日学习完整流程与重开预算、错词回练、自由练习不改变计划、学习路线和阅读词汇标记。
- 总计 **104 项测试，103 项通过、1 项跳过、0 项失败**。
- 新增 WordProgressionTests 验证级内／跨级难度、稳定记忆及“太简单”对目标的影响、遗忘降档、语言与未学卡隔离、目标上下的候选回退、无等级词书顺序，以及模拟连续 8 天学习时难度逐步上升。
- Build 9 已完成其余书库／阅读器／PDF／Coach UI 场景的完整验收，见 [Build 9 验收](testflight-9.md)。本次只重跑与新增改动相关的 UI 场景。
- `Localizable.xcstrings` JSON 解析及 `git diff --check` 通过。
- 测试结果包：`/tmp/yomiori-testflight-10/Tests.xcresult`，摘要 `test-summary.json`，日志 `tests.log`。

## 发布产物

- Release arm64 归档及 IPA 导出成功，版本 `1.1.2`、构建 `10`。
- 归档 App 和 IPA 解包 App 均通过 `codesign --verify --deep --strict`。
- Bundle ID `com.pidal.yomiori`；Team `6Y2YB464VU`；`application-identifier=6Y2YB464VU.com.pidal.yomiori`；`get-task-allow=false`。
- 应用及 ZIPFoundation 隐私清单已确认。
- IPA：`/tmp/yomiori-testflight-10/Yomiori.ipa`，19,236,265 字节。
- SHA-256：`59f8c75568bb3e147426515cff7acf741ffec7337bfc6815fd0c06d44a3a9861`。
- 沿用已验证的临时签名钥匙串流程；签名钥匙串已删除并恢复原搜索列表。
- 发布前对 99 个源码／工程／配置文件的 SHA-256 快照逐一核对，打包期间应用源码未变化；快照为 `source-snapshot.json`。

## 验证边界

词义与搭配数量是常用程度的启发式指标，记忆表现用于选词引导，不代表实际语言能力测评。真机音频、通知实际送达、真实 AI 服务和实时语音不在本次模拟器验收范围内；中英文 What to Test 已说明。

Apple 处理、测试组及审核回读见 [TestFlight 发布记录](../testflight-release.md)。
