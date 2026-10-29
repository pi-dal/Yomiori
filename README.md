# Yomiori

A SwiftUI language-learning app for reading and listening, PDF study, a personal dictionary, spaced-repetition cards, word lists, and an AI conversation coach.

**Yomiori（よみおり）** is a coined name inspired by Japanese 読み (reading) and 織り (weaving): weaving the language you encounter into your own expression. App name, Xcode scheme and module use `Yomiori`; the bundle identifier is `com.pidal.yomiori`.

Repository: [pi-dal/Yomiori](https://github.com/pi-dal/Yomiori).

```sh
git clone https://github.com/pi-dal/Yomiori.git
cd Yomiori
```

## Project

- `Yomiori.xcodeproj`: app and test targets, with the shared `Yomiori` scheme.
- `Yomiori/`: SwiftUI app, bundled resources, and English / Simplified Chinese localization.
- `YomioriTests/`: word lists, localization, AI protocols, cancellation/recovery, reader rendering, and ZIP export tests.
- `YomioriUITests/`: standard iOS Simulator acceptance for Markdown/streaming, reader selection/lookup, license navigation, and system sharing to Files.
- `docs/ai-service.md`: the API contract for connecting your own AI backend.
- `docs/architecture-review.md`: architecture findings and suggested follow-up work.
- `word-list-kit/` and `word-list-kit.zip`: generation instructions, JSON schema, validator, and a small original example for custom word lists.

## Build and test

Open `Yomiori.xcodeproj` in Xcode with Swift 6.2 and the iOS 26 SDK or newer (validated with Xcode 27). The deployment target is iOS 26.0. Select the `Yomiori` scheme and an iPhone simulator, then build and run. For device builds, select your own signing team and provisioning settings.

Command-line example on a Mac with a compatible simulator installed:

```sh
xcodebuild -project Yomiori.xcodeproj -scheme Yomiori \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' build
xcodebuild -project Yomiori.xcodeproj -scheme Yomiori \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
```

Local import, reading, dictionary and review features store learner data on the device. This is a sanitized source snapshot, published without the original private development history. Configure AI inside **Read → Settings → AI service**, using OpenAI Responses, Chat Completions or a custom relay. Enter the full HTTPS endpoint, model and optional API key (stored in Keychain), then test and save. See [AI configuration and protocol details](docs/ai-service.md). The app includes no analytics or feedback submission client. No service credentials or learner database are included. The unverified debug sample audio is omitted; the optional audio seed safely skips it. Reading, PDF import, local dictionary, word lists and review remain available. AI features require your own service configuration. See [the architecture review and changes](docs/architecture-review.md) and [the FlowDown package comparison](docs/flowdown-packages.md).

## Modern rendering and export

Coach assistant replies use MarkdownView 4.8.4 for headings, lists, tables, code blocks and streaming text. Ordinary reader text uses Litext 3.6.5 for native selection handles, magnification and lookup menus. Japanese furigana retains the existing CoreText word-boundary layout, sharing the same learning annotations. ZIPFoundation 0.9.20 packages Anki CSV, audio and import instructions into one ZIP; extract it before importing into Anki. Exported flags are saved after sharing completes.

Direct dependencies have exact version requirements; `Package.resolved` locks transitive versions. See [integration details and compatibility limits](docs/flowdown-packages.md). Debug builds accept `--component-preview` for an in-memory rendering/export fixture.

## Custom word lists

Start with [the format guide](word-list-kit/format.md) and [generation instructions](word-list-kit/SKILL.md). Validate a generated file with:

```sh
python3 word-list-kit/validate.py path/to/word-list.json
```

Import the validated JSON through the app's Files import flow.

## Third-party content and attribution

The bundled IELTS word list is adapted from [Word Atlas](https://github.com/designfuchen/word-atlas), credited to Word Atlas contributors, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Its learning text is AI-generated, is not an official IELTS list, and is not affiliated with IELTS partners. Text is preserved; the JSON keys and envelope were adapted for Yomiori. The source, license, attribution, modification notice and AI-content marker remain embedded in `Yomiori/word-atlas.json` and displayed by the app. Preserve these notices when redistributing that dataset.

Open-source dependency and bundled font notices are included in `Yomiori/ThirdPartyNotices.txt`, available from **Settings → Credits → Open source licenses**. Preserve these notices when redistributing the app.

This content license applies to the attributed Word Atlas dataset; it does not automatically license the app's code. No repository-wide open-source code license is granted here.
