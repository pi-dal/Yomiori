# Native interface and original-layout PDF acceptance

This revision supersedes the green palette, oversized artwork and card treatment described in `liquid-glass.md`. The app uses system colors, lists, navigation and sheets, with glass restricted to navigation/control layers. The supplied App icon is retained.

Device: iPhone 18 Pro Simulator, iOS 27, Xcode 27. Deployment target: iOS 26. Review performed in the current Pi session.

## Findings and changes

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM, resolved | `Yomiori/Theme.swift` | Green reading surfaces, large capsule actions | Semantic system backgrounds, system blue, native controls, white primary-button labels | Quiet surfaces and legible platform hierarchy |
| MEDIUM, resolved | `Yomiori/ReadView.swift` | Large decorative reading illustration | Native empty state and library rows | Prioritize reading material and its next action |
| HIGH, resolved | `Yomiori/DocumentsView.swift` | Bilingual PDF text extraction rebuilt the page | Original PDFKit page plus separate Chinese translation sheet | Preserve original fonts, artwork and columns |
| HIGH, resolved | `Yomiori/PDFSelectionTranslation.swift` | Experimental overlay stretched or clipped translation | Native sheet with scrollable original/result, expandable detents, explicit close and menu | Complete readable translation without custom overlay geometry |
| HIGH, resolved | `Yomiori/PDFReader.swift` | System presentation could clear the range used by annotation | Retained PDF selection and gesture-aware presentation delay | Highlight and note actions stay tied to the original selected text |
| HIGH, resolved | `Yomiori/CoachView.swift` | Accessibility-size empty-state text painted over the input composer | Intrinsically sized text stack inside a clipped scroll viewport | Large text remains scrollable and the input stays independent |

## PDF behavior

Tap a word or use PDFKit selection. Translation is requested in Chinese once selection settles. A system sheet opens after the selection gesture finishes. This sheet temporarily covers the lower viewport and dims the background; it does not resize, reflow or rewrite the PDF. Closing resumes ordinary reading. Translation itself never writes to the imported file. Explicit highlight/underline actions save annotations.

The sheet contains the selected original, the full Chinese result, retry on failure, copy-original and copy-translation actions, highlight, underline and notes. Long content scrolls; larger detents provide more space. Rapid selection changes cancel stale translation; identical text uses a per-reader cache.

## Verification

- 53 unit/integration tests passed, including translation caching, source-language identity, failure/retry, stale-response rejection, retained-range annotation, and unchanged PDF page rendering/bounds/view frame/scale.
- Final complete run: **53 unit/integration tests and 9 UI tests passed**. Result: `/tmp/yomiori-native-ui/FinalNative.xcresult`. Includes short-word translation, closing/resuming/turning pages, long-selection translation and saving a note, navigation/import, Markdown/selection and export regressions.
- Actual dark mode was set with `simctl ui ... appearance dark`. The destination/settings test and both PDF tests passed: `/tmp/yomiori-native-ui/NativeDark.xcresult` (3 tests). Dark Read and PDF translation screenshots were visually inspected.
- After the Coach large-text correction, both Chinese accessibility-size and main-destination/input tests passed: `/tmp/yomiori-native-ui/CoachFinal.xcresult` (2 tests). The final Chinese Coach screenshot was inspected; large content scrolls within its viewport above the input composer.
- Representative final screenshots: [Original PDF](native-reading/pdf-original.png), [Chinese translation](native-reading/pdf-selected-chinese.png), [Long selection](native-reading/pdf-long-selection.png), [Dark translation](native-reading/pdf-selected-chinese-dark.png), [Read](native-reading/phone-read-light.png), [Accessible Coach](native-reading/phone-coach-chinese-accessibility.png).
- Full-run captures with “dark” in their names did not control the simulator appearance; the actual dark captures above replace them. Tests use a stub translation, not a live AI response.
- The PDF fixture is a synthetic two-page document with titles, two columns, shapes and a figure panel. Preview translation is deliberately deterministic and labeled as a test translation. Fixtures run only under explicit DEBUG launch arguments, using an in-memory model container.
- The long-selection fixture injects a native PDFSelection to test the sheet and note workflow. Actual dragging of native selection handles is not covered by that fixture.
- Not verified: live AI translation quality/network behavior, scanned-image PDFs without a selectable text layer (no OCR has been added), real-device performance, VoiceOver/hardware-keyboard traversal and animation replay at 10% speed.

The separate translation sheet is an implementation choice, not a recorded user approval of the final interaction. The latest changes have not been uploaded to TestFlight.

Review disposition: **Approve** for the inspected simulator states; unverified coverage listed above is excluded.
