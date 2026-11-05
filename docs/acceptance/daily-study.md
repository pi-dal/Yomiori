# Daily learning automation

Implemented 2026-11-05 after the user asked to automate daily study and reminders. Source baseline: `aa4bebd` (1.0 (5)). Released in TestFlight **1.0 (6)** on 2026-11-05; Apple approved beta review and both internal/external states are `IN_BETA_TESTING`. See [release record](../testflight-release.md).

## Learner flow

Read now exposes Today’s study above the library and in its empty state. Starting it prepares the available workload and opens review directly. After review, the daily screen shows completed cards, any scheduled relearning time, and a route back to the saved reading position.

Defaults: 30 completed cards per calendar day, with at most 5 newly introduced words. Due old cards take priority; new cards use the remaining capacity. Starting or reopening cannot reset the budget or repeatedly add new words. New cards come from the current learning language; previously studied cards remain eligible across languages. Automatic sourcing prefers saved vocabulary with existing definitions, then an available list in the learning language. A specific list or saved-only sourcing can be selected. There is no bundled Japanese list; Japanese learners need saved vocabulary or an imported Japanese list. Choosing a source does not delete existing cards.

Reading’s primary card action now says Save & add to review when automation is enabled and preserves the existing sentence/audio mining. Quick dictionary saves also create a review card from the existing definition. Existing saved words are gradually backfilled into the daily budget. This can be disabled in settings. Word matching deduplicates normalized terms within a language; sentence-mining’s existing source/sentence safeguards remain. No new AI requests are made by daily preparation.

Ratings save immediately, with restored in-memory values on save failure. Optional first-reviewed, last-reviewed and last-completed dates persist on Card. Daily completion counts distinct successfully remembered cards. Again schedules relearning ten minutes later rather than immediately appending the card to the same queue. The finished screen identifies that pending time. Old cards upgraded without a first-reviewed date are not miscounted as newly introduced words.

## Reminders

The learner enables local notifications explicitly from the daily screen or Settings → Daily learning & reminders. Default time is 20:00 local time and can be changed. Denied permissions show an explanation and a link to system settings. One local notification is scheduled per day for a rolling 30-day window. Launch, foreground and significant calendar/time changes reconcile the schedule. Completing available work removes today’s pending reminder, retaining future dates. Turning reminders off and clearing app data cancel the managed requests. Tapping a managed notification routes into today’s study, including a cold-start pending route.

Request identifiers are persisted and generation-specific so overlapping asynchronous refreshes cannot leave old notifications active. DEBUG library fixtures do not modify production notification schedules.

The 30-day schedule renews when the app opens. Delivery is subject to the device’s notification permission and Focus settings. No remote push service or background AI execution was introduced.

## Verification

Xcode 27 / iOS 27 simulator / iPhone 18 Pro:

- Full unit run: **74 tests in 14 suites passed**, including seven new daily-study/reminder tests (`/tmp/yomiori-daily-study/FinalAcceptance.xcresult`).
- Additional final daily-study run: **8 tests passed**, including a new disk-store close/reopen test and all seven previous tests (`PersistenceAndDark.xcresult`). There are **75 distinct passing unit tests** across these runs.
- **5 UI scenarios passed**: direct daily start → five ratings → completion → reopening with retained budget; Chinese maximum accessibility settings including scrolling to the reminder control; text/PDF position restoration; Chinese voice entry; local lookup/save and voice settings.
- The daily completion/reopen UI scenario also passed with the simulator explicitly in **dark appearance**.
- Final unsigned device **Release build succeeded** (`/tmp/yomiori-daily-study/release-build.log`).
- `git diff --check` and localization JSON validation passed.

Reminder tests use an injected notification client and verify authorization, managed request contents, cancellation, completion suppression, denied permission, and route handling. Calendar tests cover past reminder times and DST. Actual timed lock-screen delivery, physical-device notification taps, and a complete VoiceOver run have not been verified.

Earlier failing test runs exposed an incorrectly retained in-memory test container and ambiguous element queries; both were repaired. The first screenshot pass exposed two missing reminder strings; English and Simplified Chinese translations were added and confirmed in the next capture.

## Evidence

- [Direct entry into review, light](daily-study/daily-study-starts-directly-light.png)
- [Completed day, light](daily-study/daily-study-complete-light.png)
- [Completed day, dark](daily-study/daily-study-complete-dark.png)
- [Chinese maximum accessibility daily screen](daily-study/daily-study-chinese-accessible-light.png)
- [Chinese maximum accessibility reminder control](daily-study/daily-study-reminders-chinese-accessible-light.png)

Screenshots use isolated in-memory fixtures. They establish layout and navigation behavior, not production learning results or live AI accuracy.
