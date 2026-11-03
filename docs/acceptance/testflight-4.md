# TestFlight 1.0 (4) verification

2026-11-03. User authorized publishing the updated app and committing/pushing the working tree. Release uses the existing app and tester groups.

## Changes included

Washi, sumi and matcha light/dark colors; Mincho Japanese and serif English reading typography with Chinese interface fallback; line transitions and media spoken progress; Off / Tap to reveal / Always show translation modes. Includes the previously local library search/sort, resume, native PDF reader, selection translation and source-navigation fixes.

The release workflow changes the build number to 4 in Debug and Release. A UI regression test verifies that the hidden translation's accessibility label does not reveal its contents, tapping reveals the current gloss, stepping re-hides the next gloss, and a second tap hides it again.

## Verified

Xcode 27, iPhone 18 Pro simulator, iOS 27.0:

- Full unit run: **54 tests in 12 suites passed** (`/tmp/yomiori-testflight-4/UnitTests.xcresult`).
- Light appearance: **6 UI tests passed** (`Acceptance.xcresult`): Chinese maximum accessibility search recovery; main destinations/import/Coach composer; text and PDF position restoration; translation reveal/reset; long PDF translation/notes; original PDF selection and automatic Chinese translation.
- Dark appearance: **2 UI tests passed** (`DarkAcceptance.xcresult`): destinations/settings and translation reveal/reset.
- Release arm64 archive and export succeeded. Both archive app and extracted IPA passed `codesign --verify --deep --strict`. Verified version 1.0, build 4, bundle `com.pidal.yomiori`, distribution application identifier `6Y2YB464VU.com.pidal.yomiori`, disabled debug entitlement and two privacy manifests.
- Temporary signing keychain removed and original keychain search list restored.
- JSON resources and `git diff --check` passed; changed text files were checked for common credential patterns with no matches.

Representative exported screenshots:

- [Revealed translation, light](testflight-4/reader-translation-revealed-light.png)
- [Hidden translation after stepping, light](testflight-4/reader-translation-hidden-light.png)
- [Revealed translation, dark](testflight-4/reader-translation-revealed-dark.png)
- [Hidden translation after stepping, dark](testflight-4/reader-translation-hidden-dark.png)
- [Chinese maximum accessibility search recovery](testflight-4/chinese-accessible-search-light.png)

Screenshots use isolated DEBUG fixtures. PDF tests use the existing deterministic translation fixture; they do not establish live AI accuracy. Simulator checks do not establish real-device performance or complete VoiceOver behavior.

## Apple result

Build/upload/beta review ID: `af7ae4fc-fa5a-465e-87ef-bad2ebf155b4`. Apple processed the build as `VALID` and approved beta review (`APPROVED`). Internal and external states are both `IN_BETA_TESTING`, with `autoNotifyEnabled=true`. The existing Internal Testers group retains all-build access and Yomiori Email Testers is explicitly associated. English and Simplified Chinese What to Test notes were created and read back.

Archive, IPA, upload receipts, signing manifest and Apple JSON evidence are under `/tmp/yomiori-testflight-4/`. IPA SHA-256: `fae955272a1b6ea18a24d23b12ca2130489f739b205f754b7ae9aaebdc85887f`.

This is a TestFlight release. No production App Store submission was made.
