# Live Coach and dictionary verification — 2026-11-03

Implemented locally against the existing washi/ink native design. This feature has not been uploaded to TestFlight.

- Final Swift Testing run: 60 test cases reported, 59 executed successfully and 1 physical-audio test explicitly skipped. This includes the existing regression suites plus deterministic realtime session tests, offline search/save tests and the simulator preflight check.
- Final native UI run: 2 tests passed, covering local IELTS `abandon` lookup, explicit dictionary save / disabled saved state, voice entry, settings, and Chinese dark appearance.
- iPhone arm64 Release build passed with `CODE_SIGNING_ALLOWED=NO`.
- `git diff --check` passed.
- Native audio probe failed twice in Apple's CoreSimulator RemoteIO initialization with SIGABRT (`AURemoteIO::Initialize → AVAudioEngine mainMixerNode`). The feature now rejects live microphone start in Simulator before RemoteIO is initialized. This failure is not reported as successful audio acceptance.
- The physical iPhone audio test is opt-in via `YOMIORI_AUDIO_DEVICE_TEST=1`. No physical-device acoustic test or valid-key Qwen session was completed.

Final results: `/tmp/yomiori-live/Verified.xcresult`; log `/tmp/yomiori-live/verified.log`; device build log `/tmp/yomiori-live/device-final.log`. Protocol test coverage includes session negotiation, raw PCM serialization, audio dispatch, speech interruption / late-chunk suppression, mute, teardown, transcript deduplication and completed-message persistence. Test transports supply synthetic server events, not evidence of provider availability.

Screenshots:

- [Live entry](live-coach/live-ready.png)
- [Chinese dark live entry](live-coach/live-chinese-dark.png)
- [Voice settings](live-coach/voice-settings.png)
- [Saved local lookup](live-coach/lookup-saved.png)

One grouped screenshot inspection found duplicate lookup results after saving; the final version filters by normalized headword and removes the resulting empty group. Audio lifecycle checks also separated background AVAudioSession activation/deactivation and guarded simulator startup. Existing reading/PDF behavior and supplied artwork are preserved.

Still required before claiming real Live readiness: physical iPhone capture/playback, Bluetooth/speaker echo and interruptions, a valid Qwen regional workspace/key, end-to-end multi-turn latency, qualitative Japanese/English pronunciation/intonation feedback and live web-search behavior. The app sends original audio for model-based feedback and deliberately exposes no calibrated pronunciation score. See [setup and architecture](../live-coach.md).
