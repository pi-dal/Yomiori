# Compact library redesign

User request: buttons and the whole page felt oversized and elderly-oriented; redesign them. Preserve the Apple-native direction, supplied icon, original PDF layout and selected-text Chinese translation.

## Changes

| Severity | Location | Before | After | Principle |
| --- | --- | --- | --- | --- |
| MEDIUM, resolved | `Yomiori/Theme.swift` | Large pill primary actions and centered unavailable-content screens | Compact inverted black/white actions, 12pt radius, left-aligned introductory state | Visual density, hierarchy and consistent action treatment |
| MEDIUM, resolved | `Yomiori/ReadView.swift` | Large system title and redundant add section | Compact content title, plain material rows, resume progress, isolated native toolbar glyphs | Content priority and operation hierarchy |
| MEDIUM, resolved | `Yomiori/DictionaryView.swift` | Four stacked word metadata lines, crowded three-action toolbar | Word/reading baseline, compact meaning/source, add plus options menu | Information density and clear action grouping |
| MEDIUM, resolved | `Yomiori/CoachView.swift` | Large illustration and inflated send/input surfaces | Text-led introduction, compact practice rows, smaller visible send circle within 44pt target | Proportion without sacrificing touch area |
| LOW, resolved | `Yomiori/SettingsView.swift` | Large identity image and inflated link rows | 48pt image, standard row heights and tighter insets | Consistent secondary-screen density |

## Evidence

- Simulator: iPhone 18 Pro, iOS 27, Xcode 27; deployment remains iOS 26. iPhone only.
- First inspection: `/tmp/yomiori-refined/Review.xcresult`, 4 UI tests passed. Included empty destinations, import, input, Chinese maximum accessibility size, and a populated in-memory library.
- Confirmation: `/tmp/yomiori-refined/Confirm.xcresult`, **6 UI tests passed**: four interface checks plus original PDF/Chinese translation and long selection/note workflow. The later addition of the missing Chinese “Recent words” localization only was checked by JSON parsing and diff inspection.
- Actual system dark appearance was explicitly set with `simctl ui ... appearance dark`. `/tmp/yomiori-refined/Dark.xcresult`: **2 tests passed**, main destination/settings and populated library.
- Final inspected evidence includes empty Read/Coach, populated Read/Documents/Dictionary, Chinese accessibility Dictionary/Coach, actual dark populated Read, and dark Settings. Initial captures with dark in the name did not control system appearance; only the explicit Dark run supplies dark evidence.
- Synthetic content is isolated behind `--library-design-preview`, DEBUG only, with an in-memory model container. These are visual fixtures, not learner-library content or real usage statistics.
- Primary styles were inspected for enabled/disabled/pressed state, 44pt targets and Reduce Motion. Shared primary styles apply to study/export actions; every secondary study/export screen was not visually revisited.
- PDF behavior was preserved and both targeted PDF tests passed. No translation or document reconstruction change in this redesign.
- Not verified: hardware performance/gesture feel, VoiceOver traversal, 10% animation replay, live AI, visual software-keyboard placement (XCTest reports a keyboard but the screenshot does not show a rendered software keyboard).

## Finish review

Review performed inline using the Impeccable degraded reviewer workflow; no independent reviewer agent was started. Native platform code and simulator screenshots were reviewed; the HTML/CSS detector does not apply. No approved comp or QUALITY BAR card was available. The Apple-native direction was carried from the explicit user brief; no new visual-world approval was claimed. PRODUCT.md remains absent; no new product interview or invented product claims were introduced.

- Persistence: DESIGN.md merged with implemented compact controls; native semantic colors retained. Missing PRODUCT.md is disclosed above.
- Fidelity: TYPE matches the compact default-size system; MATERIAL uses native controls/materials; GROUND uses semantic system white/black. Original icon and PDF layout retained.
- Ceiling: populated content and secondary action grouping were examined in addition to empty screens. Native tab bar retains its system size.
- Material fixes from inspection: Dictionary toolbar imbalance, expanded word rows and source spacing resolved; invalid document count removed.
- Keep: accessible touch targets and Dynamic Type, native navigation, PDF page fidelity.

Disposition: **ship** for inspected simulator interface states. This is a scoped implementation review, not user approval of its visual taste. Changes remain local and have not been uploaded to TestFlight.

## Representative captures

- [Read with content](refined-library/library-read-populated.png)
- [Dictionary with content](refined-library/library-dictionary-populated.png)
- [Documents with content](refined-library/library-documents-populated.png)
- [Coach](refined-library/phone-coach-light.png)
- [Read empty state](refined-library/phone-read-light.png)
- [Read in dark mode](refined-library/library-read-populated-dark.png)
- [Settings in dark mode](refined-library/phone-settings-dark.png)
