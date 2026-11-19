# Distill pass: one home per action

Goal: reduce clutter without removing features. Every removed control already had another home. Nothing in PRODUCT.md's learning path was deleted; parts of it moved one level down.

## What moved

| Surface | Before | After | Where it lives now |
| --- | --- | --- | --- |
| Today | ~25 elements in one scroll: 3 status lines, checklist, Free practice panel + footnote, stats, milestones, roadmap, reminder panel + footnote, settings row | One status line, one primary action, the 4-item checklist, then Free practice and Progress rows | Stats, milestones, roadmap and Immersion → **Progress** page. Settings → toolbar. Reminder opt-in → shown only after review is done |
| Today | CEFR minimum-level line | removed | Daily settings |
| Dictionary | Words / Cards / Lists / Review tabs; `+` pushed a second word-list screen; `···` held Immersion and Sort | Words / Cards / Lists; one Sort control on Words | Review → Today and the Cards banner. Word-list import → the Lists tab's own `+`. Immersion → Today › Progress |
| Dictionary › Cards | Start review + Free practice | Start review | Free practice → Today |
| Coach | Voice button in empty state and in composer; "Practice & improve" link and toolbar chart; lookup on every message; trash in toolbar, no confirmation | Starters + composer; lookup on Coach replies only | Voice → composer waveform. Weaknesses → toolbar. Clear chat → conversation menu, with confirmation |
| Settings | Branding card; definition toggles; Learning stage; Immersion | Languages, services, Daily learning, Anki export, Clear data, Credits | Definitions → Languages. Stage (now with its explanation) → Coach menu. Immersion → Today › Progress |

`StagePicker` was deleted because nothing called it any more.

## Verification

Xcode 27, iPhone 18 Pro simulator (iOS 27). 101 unit tests and 27 UI tests passed (DailyStudy 5, Components 4, Ink moments 2, Liquid Glass 15, Live Coach lookup/voice 1). `testLearningJourneyExposesNextActionAndRoadmap` was updated deliberately: Milestones are no longer on Today's first screen and are reached through `journey.progress`.

Evidence: `distill/*-before.png`, `distill/*-after.png`, `distill/today-dark-after.png`. These are simulator captures; they say nothing about real-device feel and do not record user approval.

Not visually verified: stage subtitles in the Coach menu (they need an open menu) and the Clear chat confirmation.

## To watch

- Free practice has fewer entry points (Today, Word book detail).
- The voice conversation is now discoverable only through the composer's waveform.

## Round 2: easy to start (user-delegated decision)

Test applied: does it help someone start learning today?

| Change | Why |
| --- | --- |
| First launch showed "You're caught up for now" and "View today" before anything existed | Read's study block is now absent until a card exists; the empty page leads with sources |
| The default language is Japanese, and the only bundled word book is English (IELTS), so a new learner had nothing to study | Empty Read asks one question, the learning language. Choosing English prepares today's first words at once. Changing language re-prepares the plan |
| "Today's study" had both a button and a "Learning path" row opening Today | The heading is the link; one action sits beneath it |
| Progress held a four-phase roadmap and milestone tiers | Removed (`JourneyPhase`, `GrowthTrack`, 20 strings). Progress keeps four plain counts and the immersion log |
| "1 of 4 anchors complete" | "1 of 4 done today" |
| 60-minute default immersion goal | 15 minutes (stepper minimum). Existing users who never set a goal will also see 15 |
| Word book page: six stat cards, title shown twice | Three plain rows (due, new, mistakes); title once, in the nav bar |

Evidence: `distill/read-empty-before.png`, `distill/read-empty-round2.png`, `distill/read-round2.png`, `distill/today-round2.png`, captured on a dedicated simulator. New UI test: `testFirstRunOffersSourcesThenStartsEnglishStudy`.

Japanese learners still start by importing material, because there is no bundled Japanese word book.
