# Crash investigation — 2026-11-03

Investigated the report of crashes across several features. These fixes do not establish the cause of every crash on the tester's phone.

## Available evidence

- App Store Connect app `6828409958`: crash submissions and beta feedback both returned zero records. The API exposes submitted feedback and may lag; this is not proof of no crashes.
- Latest uploaded build remains **1.0 (4)** (`af7ae4fc-fa5a-465e-87ef-bad2ebf155b4`). Realtime Coach in source commit `cb9413e` was not uploaded. The performance diagnostics endpoint returned resource-not-found for this build.
- No physical iPhone is connected. Local pre-investigation reports `Yomiori-2026-11-03-220252.ips` and `220446.ips` came from the earlier simulator audio probe: Apple RemoteIO initialization aborted during tests. Source already rejects realtime audio initialization in Simulator.
- Baseline: 59 Swift tests passed, 1 physical-audio test skipped; 5 UI tests passed. Ordinary reading, settings, dictionary selection and PDF selection/annotation did not reproduce a crash.

## Confirmed defects and fixes

| Path | Evidence | Fix |
| --- | --- | --- |
| Subtitle import / time formatting / export | All five invalid time fixtures were accepted. Executing `Subtitles.stamp(.nan)` killed the test process with `Double value cannot be converted to Int because it is either infinite or NaN`. | Reject nonfinite, negative, reversed and excessively large timelines; bound integer conversion; use matching 64-bit format specifiers. Validate saved timelines before rendering or translating. |
| Subtitle translation | `Dictionary(uniqueKeysWithValues:)` traps when stored subtitle IDs repeat. Previously decoded and written without ID validation. | Reject duplicate IDs on read and write, preserving the original stored blob and presenting the existing damaged-content message. |
| PDF page / selection notifications | Four-round UI stress test emitted `Modifying state during view update` during PDF navigation. PDFKit synchronously notified from representable updates and immediately wrote SwiftUI bindings. | Defer and coalesce page/selection notifications on the main queue; reject callbacks after dismantling. Added a regression for deferred callbacks and teardown. |
| Player reload / navigation | Regression test showed the previous player remained retained and old playback state survived reload. Time observer's callback strongly captured its player; reload overwrote the token without removing it. | Remove prior observation before reload, weakly capture the player, reject stale callbacks, and keep token/player ownership together for teardown. Reset playback state on load. |
| Review scheduling | Intervals multiplied indefinitely; integer conversion and forced date unwrap could trap. Negative stored review limits also reached `prefix`'s precondition. | Bound interval to 36,500 days and ease to 1.3–10, handle invalid values, provide date fallback, and bound review limit. |
| Learning time input / statistics | Arbitrarily large numeric input could produce infinite seconds, later converted directly to `Int`. | Validate input and guard stored-history formatting and totals. |
| Audio clip preview / export | Preview filename converted subtitle time directly to an integer; export constructed unchecked time ranges. | Use a unique filename and validate clip boundaries before conversion/export. |

The timeline ceiling is 315,360,000 seconds (ten years), far beyond normal imported media. Invalid stored subtitles are left intact for recovery, rather than rewritten or deleted. No schema migration or library reset is involved.

## Verification

- `/tmp/yomiori-crash-triage/Reproduce2.xcresult`: two pre-fix regressions failed, confirming import validation and player lifetime/state defects.
- `/tmp/yomiori-crash-triage/CrashReproduction.xcresult`: intentional pre-fix time conversion crash; local report `Yomiori-2026-11-03-222726.ips` belongs to this test.
- First fix attempt failed compilation due to actor-isolated deinitialization; cleanup now uses a token owner with no actor-dependent deinitializer.
- `/tmp/yomiori-crash-triage/Fixed2.xcresult`: all seven UI tests passed. The player lifetime assertion initially ran before AVFoundation released asynchronous asset loading work; the final test waits up to two seconds for release.
- `/tmp/yomiori-crash-triage/Final.xcresult`: 65 Swift tests passed, 1 physical-audio test skipped; repeated reader / PDF / settings / dictionary / Coach navigation passed across four rounds, but revealed the PDF state-update warning subsequently fixed.
- `/tmp/yomiori-crash-triage/PDFLifecycle.xcresult`: 66 Swift tests passed, 1 physical-audio test skipped; four-round navigation and both PDF UI tests passed after deferring PDF notifications. No state-during-update warning remained in this run.
- iPhone arm64 Release build passed with signing disabled (`device-release.log`). `git diff --check` passed.

## Still unresolved

No tester-device crash stack is available to connect these defects to the reported crashes. A physical-device crash report, affected screen/action, iOS version and installed build are needed to establish that connection. Existing native playback still emits warnings about synchronous AVAudioSession activation on the main thread; this is a potential hang source, not a demonstrated watchdog crash in the available evidence. True microphone, route-change and interruption testing still requires a physical iPhone and valid service credentials.

The subsequent user-authorized release packages these fixes as TestFlight **1.0 (5)**; see [release status](../testflight-release.md).
