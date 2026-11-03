# Content-first Apple-native library

User authorized implementation after rejecting repeated titles, generic icon rows and sparse form-like screens. The earlier compact-control implementation was an anti-reference, not a taste approval. This pass reconstructs main-screen composition around original reading content. Supplied app icon and original-layout PDF reading are preserved.

## Implemented

| Surface | Change | Behavior preserved or checked |
| --- | --- | --- |
| Read | One native large title, current original passage, source and compact resume link, recent source excerpts | Resume opens existing reader and back navigation works; delete remains a swipe action |
| Empty Read | Three direct source choices instead of a no-content notice | Media/subtitle import targets existing importers; link opens existing link sheet; toolbar Import retains Photos/podcast/language choices |
| Documents | Real PDF first-page thumbnails in adaptive cover grid | Opens existing DocViewer; Delete context menu and accessibility action retain confirmation |
| Dictionary | Removed duplicate title/count/recent heading; word uses Title 2, compact reading and meaning/source | Existing search, filter, lists, cards and review routes retained; zero timestamps omitted |
| Coach | Combined language/stage menu, AI information inside menu, three editable starters | Starter fills input without sending; Send enables with text; input stays in bottom safe area |
| Accessibility | Content scrolls at maximum size; send circle and hit region grow with arrow | Maximum-size starter can be reached, selected and edited |

## Evidence

Xcode 27, iPhone 18 Pro simulator, iOS 27; app deployment remains iOS 26, iPhone target. No new shipping raster asset was created; covers are runtime thumbnails of the learner's document. Preview content is synthetic and isolated behind DEBUG `--library-design-preview`, in memory. The fixture PDF labels itself synthetic. English meanings in the fixture are fixture data independent of the interface language.

- `/tmp/yomiori-content/Review.xcresult`: first inspection, **6 of 7 passed**. Both PDF tests passed: exact original-page/automatic Chinese-selection flow and long translation/note flow. The populated-library test failed because it queried a navigation-link label as a Button; test locator corrected to tap its visible source title.
- `/tmp/yomiori-content/Confirm.xcresult`: **5 of 5 UI tests passed** after the composition fixes. Covers main destinations, import menu, editable starter/Send state, populated reader/document navigation, Chinese populated screens and maximum accessibility size.
- `/tmp/yomiori-content/Dark.xcresult`: **2 of 2 passed**, after explicitly setting simulator appearance dark. Covers populated library and empty destinations/settings. Screenshots whose names contain dark from the light Confirm run were not used as dark evidence.
- `/tmp/yomiori-content/SendSize.xcresult`: **2 of 2 passed** on rebuilt final app, in actual dark appearance, after fixing the maximum-size arrow overflowing its fixed circle. Rechecked maximum Chinese accessibility input and ordinary destination/import/starter flow.
- `git diff --check`, string-catalog JSON and sidecar JSON validation passed.

## Review

Impeccable and better-ui were applied. Native code was reviewed without the HTML/CSS detector. No independent subagent mechanism was used; finish review was substituted inline using the skill's degraded workflow. No generated comp or random concept selection: user-pinned Apple-native/content-first direction carried the work. PRODUCT.md, the surface contract, DESIGN.md and its sidecar record the decision and implementation.

Initial visual fixes: remove duplicate featured chevron, move language below the excerpt, shrink empty-state prompts, expose direct link action, wrap conversation settings text. The final review identified maximum-size Send geometry; fixed with ScaledMetric and recaptured. Verdict: **ship for the two scored finish fixes and inspected simulator states**. This does not claim user taste approval.

Not verified: real-device gesture feel/performance, live AI quality, complete VoiceOver traversal, slow animation replay, many-document grid behavior, populated grids at maximum accessibility size, older iOS device appearances. XCTest reports keyboard focus/typing but software keyboard is not rendered in these captures. Library previews intentionally include one document; no full-library density claim is made. No broad unit-suite rerun was needed for this UI-only change. PDF tests ran before the final isolated Coach Send fix.

Changes remain local; no TestFlight upload.

## Captures

- [Read, populated](content-first-library/library-read-populated.png)
- [Read, Chinese](content-first-library/library-read-chinese.png)
- [Read, empty](content-first-library/phone-read-light.png)
- [Documents](content-first-library/library-documents-populated.png)
- [Dictionary](content-first-library/library-dictionary-populated.png)
- [Coach, Chinese](content-first-library/phone-coach-chinese.png)
- [Read, actual dark](content-first-library/library-read-populated-dark.png)
- [Coach, actual dark](content-first-library/phone-coach-dark.png)
- [Maximum-size Coach input, final actual dark](content-first-library/phone-coach-chinese-accessibility-input-dark.png)
