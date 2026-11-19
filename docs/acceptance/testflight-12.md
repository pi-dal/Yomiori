# Yomiori 1.1.3 (12) release acceptance

Release scope: simpler first-run language selection and Today/Progress navigation; fewer duplicate Dictionary, Coach and Settings controls; consistent PDF highlight persistence/deletion; shared word-book loading; source-aware card detection; file cleanup and reminder scheduling fixes. Source commit: `8bed883`.

## Verification

- Full Swift Testing suite: **53 passed, 1 physical-audio test skipped**, 54 cases across 14 suites. The earlier 99/101-test reports predate the test pruning in `bc5efd8`; this release reports the current executable suite.
- Full UI suite: **17 passed**. Combined result: **70 passed, 1 skipped, 0 failed**.
- Includes first-run English study, daily review and reopening budget, free-practice schedule preservation, Chinese accessibility settings, word selection, settings licenses, system share cancellation/save, reading/PDF position restoration, source jumps, translation reveal, PDF text selection and notes.
- Release arm64 archive/export and strict signature verification passed. Version/bundle identity, distribution entitlements, microphone/speech permissions and both privacy manifests were checked. All 100 source/configuration files matched the pre-build snapshot. Temporary signing keychain was removed and the original search list restored.
- Result bundle and logs: `/tmp/yomiori-testflight-12/Tests.xcresult`, `tests.log`.
- Runtime: Xcode 27, iOS 27 simulator, iPhone 18 Pro (`D11C224D-313C-408F-90DE-6D641B25D992`).
- Release source/configuration snapshot: `/tmp/yomiori-testflight-12/source-snapshot.json`. Build and signing receipts are retained in that directory.

## Limits

No SwiftData persisted fields were removed; the obsolete PDF translation cache field remains for compatibility. An installed build-11 database upgrade was not exercised. Simulator UI checks do not establish hardware haptics, notification delivery, full VoiceOver behavior, or real Qwen microphone/provider availability. Realtime voice remains optional and requires user configuration; these limitations are disclosed in What to Test.

Earlier design evidence and intentional entry-point changes are described in [Distill acceptance](distill.md); architecture findings are in [simplification review](../simplification-review-1.1.2.md).
