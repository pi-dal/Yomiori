# Button refinement

The existing washi, sumi and matcha visual system now has a shared action hierarchy. Primary commands use ink inversion; secondary commands use paper fill and matcha labels; inline and disclosure actions use matcha text. Native navigation, menus, alerts, pickers and switches retain their platform treatment.

## Changes

- Consolidated intrinsic and full-width primary actions into one shared surface: continuous 10pt corners, wrapping semibold labels, 48pt minimum height and a restrained 0.985 press scale. Reduce Motion removes scale; disabled controls do not animate on press.
- Added paper and text action styles with role-aware destructive colors and disabled states. Review ratings use equal paper actions without decorative borders or an implied default answer.
- Daily study settings and continue-reading actions use full-row targets with directional affordances and source details. Reminder opt-in shows a progress indicator while requesting permission.
- Unified word-list add buttons, saved dictionary states, podcast episode import, Anki export entry, Coach lookup and voice controls. Removed duplicate height padding from the Coach primary button.
- Restored matcha interaction tint in AI settings, word-list settings/import/detail and link import. Coach's enabled send action uses matcha.
- Disclosure-row icon columns scale with Dynamic Type to avoid collisions at maximum accessibility sizes.

## Verification

Device: iPhone 18 Pro Simulator, iOS 27.0, Xcode 27.0. The project targets iPhone only.

- Initial light run: 5 UI scenarios passed.
- Dark run: 3 UI scenarios passed.
- Final confirmation after layout corrections: 6 UI scenarios passed, zero failures. Coverage includes Chinese maximum accessibility settings, five-card study completion and preserved budget, main destinations/import, Chinese voice entry, local lookup/save/voice configuration, word-list add and Anki export entry.
- Debug build and `git diff --check` passed.
- Reviewed simulator captures of study home/completion, review ratings, Coach, voice setup, saved dictionary state and word-list actions in light/dark appearance. Evidence: `button-refinement/`.

Result bundles and logs: `/tmp/yomiori-buttons/Light.xcresult`, `Dark.xcresult`, `Final.xcresult` and their adjacent logs.

The orientation transition ran during study acceptance, but its screenshot contained an incomplete rotated frame. Those captures were excluded from the evidence; landscape visual acceptance remains unconfirmed. Active network voice controls were inspected in code rather than exercised against a live service. Physical-device feel and VoiceOver navigation were not verified in this pass.

Released with daily learning automation in TestFlight **1.0 (6)** on 2026-11-05 after the user's explicit commit/push/release request. Apple approved beta review and both internal/external states are `IN_BETA_TESTING`. See [release record](../testflight-release.md).
