# Liquid Glass UI acceptance

Historical record for the earlier green treatment shipped in TestFlight 1.0 (2). The subsequent Apple-native redesign and original-layout PDF work are documented in [native-reading.md](native-reading.md).

Device: iPhone 18 Pro Simulator, iOS 27.0, built with Xcode 27. Deployment target remains iOS 26. The app targets iPhone only.

Applied `/better-ui` and Impeccable native iOS guidance. The user pinned Liquid Glass and supplied the new artwork. Review was performed in the current session without an independent review agent. No web detector ran because the changed interface is native SwiftUI.

## Surfaces and structure

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM, resolved | `Yomiori/YomioriApp.swift:89` | Hidden native tabs, custom tab bar, opaque navigation appearance | Native TabView, system navigation and scroll minimization | Native glass and safe-area ownership remain consistent across destinations |
| MEDIUM, resolved | `Yomiori/Theme.swift:87` | Underlined text tabs | System segmented picker; scrolling accessible-size buttons | Platform selection behavior and a persistent selected state |
| MEDIUM, resolved | `Yomiori/Theme.swift:124` | Sparse empty states and isolated dividers | Shared heading, explanation and primary action | Consistent hierarchy and a clear next step |
| MEDIUM, resolved | `Yomiori/CoachView.swift:195`, `Yomiori/ReaderView.swift:247` | Opaque input/player strips | Native glass floating control surfaces | Distinguish controls from reading content with system material |
| MEDIUM, resolved | `Yomiori/SettingsView.swift:60` | Plain settings list | Native inset grouped settings | Related preferences are grouped and recognizable |

## Motion, icons and images

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM, resolved | `Yomiori/Theme.swift:153` | Flat primary button with no tactile feedback | Capsule action, 0.96 press scale, 150 ms curve, Reduce Motion and static opt-out | Precise, interruptible press feedback |
| MEDIUM, resolved | `Yomiori/ReaderView.swift:247` | Abrupt play/pause glyph replacement | Persistent overlapping symbols using 0.25–1 scale, 0–1 opacity, 4–0 blur, 0.3-second spring, zero bounce | Context stays recognizable throughout the state change |
| MEDIUM, resolved | `Yomiori/Theme.swift:190`, `Yomiori/Assets.xcassets/AppIcon.appiconset` | Previous icon and no brand artwork | User illustration as normal/dark icon and reading artwork; 10% pure black/white in-content outline | Brand continuity and consistent image depth |

## Verification

- Full run: **48 unit/integration tests and 7 UI tests passed**. Result: `/tmp/yomiori-ui/Acceptance.xcresult`.
- Actual system-dark appearance was subsequently selected with `simctl ui ... appearance dark`; all four destinations and Settings were recaptured and their UI test passed. Result: `/tmp/yomiori-ui/Dark.xcresult`. A launch argument alone had not switched the first set of captures, which were replaced.
- Light destination/import and Chinese accessibility-size UI checks passed after the layout corrections. Result: `/tmp/yomiori-ui/Final.xcresult`.
- Final Chinese copy/accessible segmented-button changes passed the localization tests and Chinese accessibility-size UI test. Result: `/tmp/yomiori-ui/LocalizationFinal.xcresult`.
- Captures inspected: Read, Documents, Dictionary, Coach in light/dark, dark Settings, Import sheet, Chinese accessibility-sized Read/Dictionary/Coach. Representative images are stored in `docs/acceptance/liquid-glass/`.
- Input disabled/enabled state and text entry passed. XCTest reported a keyboard element, but screenshots did not show the rendered software keyboard; **software-keyboard visual layout: Not verified**.
- Native selection/lookup, Markdown streaming, license navigation, and share-cancel/save-to-Files regression tests passed.
- Primary-button and playback-motion values, disabled styles, loading/error branches and Reduce Motion branches were inspected in source.
- Hover, hardware-keyboard focus traversal, live AI errors, populated library/review layouts after restyling, real-device performance, Reduce Transparency on hardware, and animation replay at 10% speed: **Not verified**. No live AI request was needed for this visual change.
- The only remaining build warning is skipped AppIntents metadata extraction because the target has no AppIntents dependency. Artwork catalog warnings were corrected.

Review disposition: **ship** for the inspected primary destinations and states. **Approve** at that scope; unverified coverage above is excluded.
