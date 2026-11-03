# Reading position and recovery verification

Native iPhone refinement using Impeccable. Review performed inline by the current session, without an independent reviewer or web detector. Device: iPhone 18 Pro, iOS 27 simulator, Xcode 27. No new shipping raster assets.

## Findings and applied changes

| Finding | Resolution | Evidence |
| --- | --- | --- |
| PDF Continue reading opened the correct title but reset page 2 to page 1 | Ignore initial PDFKit page notifications; restore the clamped requested page after initial layout before publishing page changes | Failed in Review, passed in Confirm and actual-dark Final |
| Stored PDF position could exceed the document's real length | Load actual page count and clamp position before creating the reader | Synthetic saved page 99 opens page 2 of a two-page PDF; boundary Next action disabled |
| Source navigation could re-push the reader after Back | Consume subtitle jump request on arrival; listen for a changed time in an existing reader | First source-jump test failed to recover library tabs; after fix, consecutive jumps to lines 1 and 2 of the same source and Back passed |
| Source navigation only observed identity | Read observes time as well as ID; active text/PDF readers handle changed target positions | Subtitle dictionary route exercised twice. Already-mounted PDF same-document jumps inspected in code, not separately driven by UI test |
| Pure text navigation lacked an explicit position/action pair | Native bottom toolbar shows line position, Previous/Next line; boundaries disabled. Root tabs hide in focused reader | Line 2 → line 3 → library → resume line 3 → previous line 2; light and dark captures |
| Featured identifier propagated to all child texts | Identifier attached to Button | Exact featured-button lookup and activation now pass |
| Recovery action looked like static text; sort heading read “Title” | Blue Clear search action; localized “By title” section label | Chinese largest-size recovery and sorted library captures |
| Last-opened identifiers lingered after source deletion | Clear matching identifier on deletion | Delete filtered reading result, then remaining materials; delete last PDF and verify options absent |

## Verification results

- `/tmp/yomiori-verify/Review.xcresult`: Chinese maximum-size search recovery, filtered/last reading deletion, and existing search/sort/resume passed. Position test exposed PDF page reset; that run is not reported as passing.
- `/tmp/yomiori-verify/Confirm.xcresult`: PDF obsolete-position/deletion, text/PDF position recovery, and both PDF selection/translation/note UI tests passed. Source-jump Back test exposed an unconsumed jump and failed before the fix.
- Same Confirm bundle: six unit tests passed (five PDF translation/cache/cancellation/annotation/rendering tests plus natural title ordering).
- `/tmp/yomiori-verify/Final.xcresult`: **3/3 passed** after explicitly switching simulator appearance to dark: Chinese maximum-size search recovery, text/PDF positions, and repeated source navigation/Back.
- Overall, **eight distinct UI scenarios and six unit tests have passing runs** for this scoped work. This is not one eight-test clean suite run, and not the full test suite.
- Diff whitespace check and localization JSON parsing passed. Simulator appearance restored to light afterward.

## Finish review

`disposition: ship` for the repaired position/recovery flows and inspected screenshots. This is a scoped engineering/visual judgment, not user approval or a complete product audit.

- Persistence: PRODUCT.md and the surface brief retain the established content-first direction; DESIGN.md now describes reader line controls, jump consumption and PDF restoration.
- Fidelity: TYPE matches responsive native styles and original serif previews. MATERIAL uses native toolbars/search and original PDF pages. GROUND follows semantic light/dark surfaces, while PDF remains its original white page. No reconstruction, invented content or decorative imagery added.
- Ceiling: system navigation, focused-reader toolbar and explicit position improve operation without introducing another custom panel.
- Material fixes: inspected reset, Back and deletion defects resolved. Existing-reader PDF jump remains a code-reviewed path without a dedicated UI scenario.
- Keep: original PDF typography/layout, selected-text Chinese translation, existing notes, Dynamic Type, semantic colors and native navigation.

## Limits

Fixtures are synthetic and isolated in an in-memory library. Restore checks cover returning to the library and reopening within one app run, not process termination/relaunch persistence. No hardware gesture/performance claim, full VoiceOver traversal, iOS 26 rendering pass or broad regression-suite claim. Software keyboard focus/typing is exercised but simulator captures omit its rendered keyboard. No TestFlight upload.

## Captures

- [Text line controls, light](reading-verification/text-reader-last-line.png)
- [Text line controls, dark](reading-verification/text-reader-last-line-dark.png)
- [PDF actually restored to page 2](reading-verification/pdf-resumed-page-two.png)
- [PDF restored in dark appearance](reading-verification/pdf-resumed-page-two-dark.png)
- [Library after repeated source jumps and Back](reading-verification/reading-after-source-jumps-dark.png)
- [Chinese maximum-size search recovery](reading-verification/chinese-accessible-search-recovery-dark.png)
- [Empty library after deleting last PDF](reading-verification/documents-after-last-delete.png)
