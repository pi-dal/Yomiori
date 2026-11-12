# English word difficulty — 1.0 (7)

2026-11-05. English daily learning uses the source word list's CEFR level as a configurable minimum for new vocabulary. The default is B1; the learner can choose A1–C2 or all levels in Daily learning & reminders. Existing due reviews continue to follow their schedule. Unranked vocabulary stays eligible, and previously saved cards are not retroactively ranked.

Word-list insertion copies the source level into `Card.wordLevel` with an empty default for older stores. Word-list rows and newly created review cards show the level. The source corpus's levels remain learning guidance, not a verified assessment of learner proficiency.

## Verification

- Final unit run: 77 tests in 14 suites passed on iPhone 18 Pro / iOS 27.0 Simulator using Xcode 27.0.0. Covers default English minimum, opt-out to all levels, Japanese behavior, filtering ranked new cards, bounded/deduplicated corpus preparation, and copying source levels into cards.
- Existing UI acceptance run: 26 tests passed, including Daily Study completion/reopening and Chinese accessibility settings, reading, PDF, lookup and voice configuration. This run preceded the final correction to a unit test fixture's due dates; app source did not change afterward.
- Localization catalogue parses as JSON and `git diff --check` passes.
- Release arm64 archive and App Store Connect IPA export succeeded. Strict code-signature verification passed for archive and unpacked IPA. Version `1.0 (7)`, bundle ID `com.pidal.yomiori`, application identifier `6Y2YB464VU.com.pidal.yomiori`, `get-task-allow=false`; two privacy manifests present.
- Temporary signing keychain removed and original keychain search list restored.

## Limits

No dedicated visual acceptance was recorded for the new English level picker and level labels. No installed build-6 database migration was tested end to end. Real-device notifications and live voice service are outside this simulator evidence. Existing cards with empty levels continue to appear, so the minimum cannot filter those until their metadata is known.

Artifacts: `/tmp/YomioriDerived/Logs/Test/` and `/tmp/yomiori-testflight-7/`.
IPA SHA-256: `90b8ea605bdca60ad1268ede0da27c59e5a4be69f47a9ad9ef3277cc7f3930fe`.
