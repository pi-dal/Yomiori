# Ink moments

Simulator evidence (iPhone 18 Pro, iOS 26 simulator, Xcode 27) for the study loop's acknowledgement moments. Screenshots: `docs/acceptance/ink-moments/`, produced by `YomioriUITests/InkMomentsAcceptanceTests` with the synthetic `--daily-study-preview` fixture. One fixture card (喫茶店) now starts at a 10-day interval so recalling it shows a word sticking.

| Moment | English light | English dark | Chinese, Accessibility L |
| --- | --- | --- | --- |
| Wrong choice struck, answer checked | `en-light-recall-struck.png` | `en-dark-recall-struck.png` | `zh-accessible-recall-struck.png` |
| Correct choice checked | `en-light-recall-checked.png` | `en-dark-recall-checked.png` | `zh-accessible-recall-checked.png` |
| Word has stuck | `en-light-word-stuck.png` | `en-dark-word-stuck.png` | `zh-accessible-word-stuck.png` |
| Page of words | `en-light-session-page.png` | `en-dark-session-page.png` | `zh-accessible-session-page.png` |
| Study stroke in word sheet | `en-light-word-sheet-stroke.png` | `en-dark-word-sheet-stroke.png` | — |

Chinese captures are downscaled to 800pt height. `en-dark-word-sheet-stroke.png` was taken before glyph runs were merged into one stroke span; the light capture shows the final single stroke.

Tests: 99 unit tests, `DailyStudyAcceptanceTests` (5) and `InkMomentsAcceptanceTests` (2) pass.

Limits: the simulator has no AI service, so the word-sheet lookup fails and the draw-on animation at the moment of saving was not exercised; only the settled stroke on an existing card was captured. Motion timing, Reduce Motion paths and haptics were not verified visually or on hardware. No user approval is implied.
