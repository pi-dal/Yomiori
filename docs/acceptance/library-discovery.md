# Library discovery

Continues the delegated content-first library work. Review performed inline by the current session; no independent reviewer or web detector was used. Native simulator captures are the evidence. No new shipping raster assets.

## Behavior

- Read and Documents use native collapsible search, matching titles with localized comparison. Empty/whitespace queries show the library. Nonmatching queries show a native recovery state with Clear search.
- Both menus offer Newest first and Title. Ordering persists in AppStorage; title ordering uses localized natural comparison (Chapter 2 precedes Chapter 10), with newer imports breaking equal-title ties.
- Read keeps the last opened material featured regardless of sort; searching includes that material in ordinary results. A deleted/stale stored ID falls back to an existing progressed material, then newest import.
- Documents offers Continue reading for the last opened existing PDF inside its options menu. This opens the existing viewer and saved page.
- New interface strings have English and Simplified Chinese translations.
- DEBUG library preview now isolates AppStorage preferences as well as its in-memory records. Optional scale fixture adds 240 reading records and 240 PDF records. Those PDF records share a synthetic two-page file; this is not 240 unique large files.

## Evidence

Xcode 27 / iPhone 18 Pro / iOS 27 simulator. iPhone is the shipped device class.

- Initial Review: populated library/navigation passed; new search flow stopped because the test expected Cancel, while this OS exposes Close.
- Confirm: Chinese populated destinations, document grid/accessibility edge cases, and 240-record search/open flows passed. Sorting assertion exposed an erroneous launch-argument override of persisted sort, removed afterward.
- Final: three unit tests passed (natural numeric title ordering/newest tie break, existing pluralization, existing accessibility/progress localization). Sorting screenshots show actual reordered content. Its first geometry assertion assumed a single column; corrected to account for two items in a row.
- Dark: both PDF acceptance tests passed (original geometry/automatic Chinese selection; long translation/note save). The search/sort flow reached and opened the last PDF successfully; its additional reading-featured assertion used an identifier that SwiftUI propagates and concatenates on a composed Button. Final verification uses the visible title/action label and checks the resulting reader navigation instead.
- Verified.xcresult: final dark search/sort/resume test passed, including actual taps on the last-opened featured reading and PDF resume menu, checking destination titles. Four distinct library UI tests, two PDF UI tests and three unit tests have passing runs for this scoped work; earlier failing test harness assumptions are disclosed above.

## Visual finish review

`disposition: ship` for the inspected additions and captured states, subject to the final functional verification below. No comp exists for this refinement; the established native direction is the reference.

- Persistence: PRODUCT.md, DESIGN.md and the surface contract exist. DESIGN.md includes search, ordering and last-opened behavior.
- Fidelity: TYPE matches native Dynamic Type and serif original excerpts. MATERIAL matches native search/menus and real fitted PDF thumbnails. GROUND matches semantic white/black. Navigation, source content, cover aspect ratios and accessible row adaptation remain intact.
- Ceiling: scoped refinement uses system search/menus rather than adding another custom panel. Small collections intentionally keep whitespace; dense/compact list mode remains a future product choice.
- Material fixes: none in the captured scope. The search field uses the system's automatic collapsed presentation; swipe down reveals it.
- Keep: original content, native navigation, full accessibility titles, exact PDF layout and existing selected-text Chinese translation.

## Limits

Search is title-only, not full-text PDF/subtitle indexing. Collections still load through existing SwiftData queries and sort/filter in memory. The scale test establishes lookup/navigation at hundreds of records, not device frame rate, peak memory, or thumbnail throughput for hundreds of unique large PDFs. No full VoiceOver traversal, hardware test, full unit suite or iOS 26 rendering pass was performed. Sorting preferences persist in production; preview preferences reset at fixture launch. Changes remain local; no TestFlight upload.

## Captures

- [Read after title sorting](library-discovery/reading-sorted-titles.png)
- [Documents after title sorting](library-discovery/documents-sorted-titles.png)
- [Search recovery](library-discovery/document-search-empty.png)
- [240-record document lookup](library-discovery/large-library-document-search.png)
- [Chinese reading](library-discovery/library-read-chinese.png)
- [Maximum accessibility document rows](library-discovery/library-documents-grid-accessibility.png)
