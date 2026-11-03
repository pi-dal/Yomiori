# Live Coach and quick dictionary

## User flows

Coach has a waveform button beside the composer and a voice action in its empty state. It opens a focused Live Coach sheet with Start, Mute, Interrupt and End controls. Conversation and pronunciation/intonation practice use the original microphone signal. Completed captions enter the existing Coach history; recordings are not stored by the app. Backgrounding the app, leaving the voice screen, data reset, configuration changes, audio interruption or removal of the audio route ends the connection.

Voice service is configured in Settings → Voice service, independently from text AI. Enter the WSS endpoint, model, voice and key from the same Alibaba Cloud region/workspace. The default example is the Beijing endpoint with `qwen3.5-omni-flash-realtime` / `Tina`; verify availability in your workspace. Keys are saved under a separate Keychain account. No developer service credentials are bundled. Start explicitly opens the microphone; a connection timeout or dropped audio buffer ends the session with an actionable error. Automatic reconnection does not resend a paid conversation.

Qwen3.5 and Qwen3.8 Omni realtime models can optionally search the web using `enable_search` and `search_options.enable_source`. The model decides when to search. The app shows search usage only when the server reports it; it does not fabricate sources or claim that every answer came from the web. This does not add browsing to the existing text-only completion adapter.

Dictionary → Look up a word searches saved headwords/readings/meanings and same-language bundled/imported word lists. Exact local matches work offline; otherwise Look up meaning calls the existing user-configured text AI. Add to dictionary saves explicitly and deduplicates normalized headword within the learning language. Lookup alone never writes a word. Coach messages open the same panel with tappable words; live captions also support direct word taps. The dictionary's existing search additionally includes saved notes.

## Architecture and wire format

- `LiveConfiguration`: validated WSS request, model/voice/search configuration and separate secret storage. Existing text credentials retain their original account.
- `LiveProtocol`: Qwen session update, original PCM audio, server VAD, input captions and tutor instructions. Audio feedback is qualitative model advice, not a validated pronunciation score.
- `LiveAudio`: AVAudioEngine voice processing / echo cancellation, mono PCM16 input converted to 16 kHz, streamed mono PCM16 output played at 24 kHz. Input backlog and playback backlog have hard bounds. Microphone permission is localized.
- `LiveSession`: transport/audio interfaces for deterministic protocol tests; connection/session identity, timeout, VAD interruption, cancelled-response filtering, deduplicated completed text persistence and explicit cleanup. Partial/cancelled assistant captions are not persisted as completed replies. Captions are a reference ASR output and can differ from the audio model's understanding.
- `QuickDictionary`: local search, explicit save and shared lookup view using the existing SwiftData dictionary schema.

No SwiftData schema change or new package dependency is required.

## Validation boundaries

Automated tests exercise session negotiation, raw PCM serialization, audio response playback dispatch, VAD interruption and late-chunk suppression, mute, ending a session, duplicated captions, secure URL/model/key validation, local word lookup and per-language save deduplication. Native UI checks exercise local English word lookup/save, voice entry/configuration and Chinese dark appearance.

An additional native audio test on this host reproduced an Apple CoreSimulator RemoteIO RPC timeout/abort while AVAudioEngine initialized its mixer. The crash stack was in `AURemoteIO::Initialize`, before model networking. Simulator microphone start now fails explicitly before initializing RemoteIO, so lookup/configuration UI and deterministic audio-protocol tests remain usable. The real-device capture/playback test is opt-in with `YOMIORI_AUDIO_DEVICE_TEST=1` on a physical iPhone; it has not passed here. AVAudioSession activation/deactivation uses a serial background queue to avoid blocking the main actor.

A valid Qwen realtime service key is required to verify an actual paid voice session. Simulator protocol/UI evidence does not establish model latency, acoustic echo cancellation quality, Bluetooth switching quality, Japanese pronunciation/intonation feedback accuracy or live web-search accuracy. These must be checked on a real iPhone with the intended service/workspace before claiming Live acceptance or distributing this feature as verified.

## Official protocol references

- [Qwen Omni Realtime](https://www.alibabacloud.com/help/en/model-studio/realtime)
- [Client events](https://www.alibabacloud.com/help/en/model-studio/client-events)
- [Server events](https://www.alibabacloud.com/help/en/model-studio/server-events)

The feature uses Qwen's public API, not an embedded Qwen consumer-app session. Regional endpoint/model availability follows the configured provider.
