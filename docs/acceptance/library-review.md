# Library review and optimization

⚠️ DEGRADED: single-context (no permitted isolated subagent tool exposed for this task). Native SwiftUI/PDFKit code and simulator captures reviewed; no browser/DOM overlay or HTML/CSS detector result is claimed.

## Assessment

Original excerpt and PDF-page previews make the interface specific to Yomiori. Native navigation and editable conversation starters work. The remaining weakness is rhythm and scale: reading sections had inconsistent insets and large gaps, vocabulary sources hugged overlay separators, and the fixed Coach configuration/composer consumed most of the maximum-size viewport. One-document previews had hidden layout problems.

Pre-fix heuristic judgment for the inspected screens only, not a measured product score:

| Heuristic | /4 | Observation |
| --- | --- | --- |
| System status | 3 | Position/import/Send state visible |
| Real-world match | 3 | Familiar original material and library vocabulary |
| Control/freedom | 3 | Native back, sheets, cancellation retained |
| Consistency | 2 | Inconsistent list insets/separators |
| Error prevention | 3 | Disabled empty Send, PDF delete confirmation |
| Recognition | 3 | Meaningful original content previews |
| Efficiency | 2 | Fixed large controls consume scrolling area |
| Aesthetics | 2 | Sparse composition and uneven row rhythm |
| Recovery | 3 | Existing retry and import recovery retained |
| Help | 2 | Basic contextual hints; no comprehensive help review |
| Total | 26/40 | Subjective review baseline; no fabricated post-fix score |

Cognitive load: moderate from grouping/hierarchy, rather than excessive choices. Mobile reader needs clear resume priority; accessibility reader needs useful scroll space; larger-library reader needs real grid coverage. Native visual hierarchy and original PDF content must remain intact.

## Applied changes

| Priority | Issue | Resolution |
| --- | --- | --- |
| P1 | Maximum-size Coach has fixed configuration above and up to five large input lines below | Configuration scrolls with content; accessibility composer shows up to two lines and retains the full editable text. Removed ScrollView clipping that interfered with the native large title. |
| P2 | Reading excerpt/gaps oversized; Recent and rows misaligned | Title-style excerpt, tighter internal/section spacing, explicit shared 24pt row/header insets and separator alignment. Added Chinese Recent localization. |
| P2 | Dictionary source text touches overlay separator and rows feel loose | Native bottom row separators, clear 12pt vertical insets, no leading top rule and consistent list top spacing. |
| P2 | PDF thumbnails synchronously rendered in body on updates | File-keyed task renders on a utility thread; per-view state retains result and checks cancellation before publishing. This is not a global/durable cache. |
| P2 | Landscape cover has an artificial outer page/frame; maximum-size grid hides metadata | Shadow follows real fitted page. Maximum-size layout becomes a single column with small cover beside full title/page position. Missing previews show a placeholder. |

## Verification

Xcode 27, iPhone 18 Pro, iOS 27 Simulator. App targets iPhone/iOS 26. Synthetic fixtures remain DEBUG-only, in an in-memory library; PDFs explicitly identify synthetic test content. Additional fixture includes six document records, a landscape PDF, a long title and a missing preview. No shipping image asset was added.

- `/tmp/yomiori-review/Review.xcresult`: **8/8 passed**. Six main-interface tests, including populated/Chinese/accessibility/import/input/navigation and grid edge cases; two PDF tests cover automatic Chinese selection/original geometry and long translation/note.
- `/tmp/yomiori-review/Confirm.xcresult`: **2/2 passed** after the visual fix batch. Covers reading/document navigation, final vocabulary row appearance, document grid/landscape/long title/unavailable preview and accessibility document rows.
- `/tmp/yomiori-review/Dark.xcresult`: **3/3 passed** after explicitly setting simulator appearance dark, rebuilt with final Coach title correction. Covers Chinese populated destinations, maximum-size Coach input, and all document-grid edge cases.
- Inspected final light Read/Dictionary/grid/accessibility rows and actual-dark Coach/grid/input. Confirm captures replace first-pass files where fixes changed them.
- Diff whitespace and localization/sidecar JSON validation pass.

## Finish verdict

Inline finish review; no independent agent. Persistence: PRODUCT.md, surface contract and DESIGN.md exist and describe the implemented direction. TYPE matches native dynamic type and excerpt hierarchy. MATERIAL uses original fitted pages, native presentations and flat library content. GROUND uses semantic white/black, confirmed in actual dark captures.

Fix scoring: reading alignment resolved; vocabulary separator spacing resolved; Coach fixed-region crowding resolved within captured flow; maximum-size document metadata visibility resolved; artificial landscape frame resolved. **Disposition: ship for these scoped fixes and inspected simulator states.** This is not user approval of visual taste or a complete product audit.

## Remaining opportunities

- Long titles at default size are intentionally summarized after three lines; opening the source exposes the full title. A future library search/sort feature may matter more than further styling for very large collections, but that adds product behavior beyond this review.
- Cover rendering is asynchronous per visible view, not a measured global caching solution. Profile on hardware with a large personal library before claiming scrolling performance.
- PDF page fidelity and selected Chinese translation remain unchanged. Do not reconstruct document typography to improve a library screenshot.
- Not verified: physical-device gestures/performance, full VoiceOver traversal, older OS rendering, live AI quality, software-keyboard rendering (XCTest confirms focus/typing, screenshots omit the software keyboard), many-hundred-document scale. Full unit suite was not rerun for the layout changes.

Questions skipped: user delegated optimization already; no unresolved brand/product choice required another approval. Changes remain local, no TestFlight upload.

## Captures

- [Reading, final light](library-review/library-read-populated.png)
- [Dictionary, final light](library-review/library-dictionary-populated.png)
- [Multiple documents and landscape PDF](library-review/library-documents-grid.png)
- [Accessible document rows](library-review/library-documents-grid-accessibility.png)
- [Coach, final actual dark](library-review/phone-coach-chinese-dark.png)
- [Maximum-size Coach input](library-review/phone-coach-chinese-accessibility-input-dark.png)
