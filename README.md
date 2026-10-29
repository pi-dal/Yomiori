# Kotoba

A SwiftUI language-learning app for reading and listening, PDF study, a personal dictionary, spaced-repetition cards, word lists, and an AI conversation coach.

## Project

- `Kotoba.xcodeproj`: app and test targets, with the shared `Kotoba` scheme.
- `Kotoba/`: SwiftUI app, bundled resources, and English / Simplified Chinese localization.
- `KotobaTests/`: word-list import, atlas, localization, and audio-cache tests.
- `web/`: the app's AirHost AI relay Worker source, not a marketing website.
- `word-list-kit/` and `word-list-kit.zip`: generation instructions, JSON schema, validator, and a small original example for custom word lists.

## Build and test

Open `Kotoba.xcodeproj` in Xcode with the iOS 26 SDK or newer. The deployment target is iOS 26.0. Select the `Kotoba` scheme and an iPhone simulator, then build and run. For device builds, select your own signing team and provisioning settings.

Command-line example on a Mac with a compatible simulator installed:

```sh
xcodebuild -project Kotoba.xcodeproj -scheme Kotoba \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' build
xcodebuild -project Kotoba.xcodeproj -scheme Kotoba \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
```

Local import, reading, dictionary and review features store learner data on the device. This is a sanitized source snapshot, published without the original private development history. The original AI service address is replaced with an `example.invalid` placeholder. Analytics and feedback ingestion keys are blank, and those clients do not submit while unconfigured. No service credentials or learner database are included. The unverified debug sample audio is omitted; the optional audio seed safely skips it. Reading, PDF import, local dictionary, word lists and review remain available. Configure your own services before enabling network-backed features.

The Worker source is included as a development reference. Its per-install UUID metering is not authentication or a secure billing boundary: before a public deployment, add authenticated callers, atomic usage reservations, and a global budget/rate limit. Do not expose an unrestricted paid AI relay. This publication does not change the original deployed app or service.

AirBuild's local build configuration, simulator evidence, generated build output and operational records live in `.airbuild/` and are intentionally excluded from Git.

## Custom word lists

Start with [the format guide](word-list-kit/format.md) and [generation instructions](word-list-kit/SKILL.md). Validate a generated file with:

```sh
python3 word-list-kit/validate.py path/to/word-list.json
```

Import the validated JSON through the app's Files import flow.

## Third-party content and attribution

The bundled IELTS word list is adapted from [Word Atlas](https://github.com/designfuchen/word-atlas), credited to Word Atlas contributors, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Its learning text is AI-generated, is not an official IELTS list, and is not affiliated with IELTS partners. Text is preserved; the JSON keys and envelope were adapted for Kotoba. The source, license, attribution, modification notice and AI-content marker remain embedded in `Kotoba/word-atlas.json` and displayed by the app. Preserve these notices when redistributing that dataset.

This content license applies to the attributed Word Atlas dataset; it does not automatically license the app's code. No repository-wide open-source code license is granted here.

The app retains its Made with AirBuild credit.
