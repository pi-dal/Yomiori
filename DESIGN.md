---
name: Yomiori
description: An Apple-native language library set on washi paper in sumi ink, where original content leads.
colors:
  paper: "#F5F0E6 / #1B1916"
  surface: "#FBF8F2 / #26231F"
  grouped: "#EDE7DB / #131210"
  sumi-ink: "#2B2824 / #ECE5D7"
  usuzumi: "#6B655C / #A49C8F"
  matcha: "#46663F / #A3C095"
  shu: "#B23A26 / #EE8A70"
  sakura-wash: "#EFA7B4 / #D27A8B at 42%"
rounded:
  action: "10pt"
  search: "10pt"
  composer: "16pt"
spacing:
  page: "24pt"
  related: "8pt"
  section: "24pt"
---

# Design System: Yomiori

## Overview

Yomiori is a personal reading library and language workspace. Original passages, actual PDF pages and saved words establish its character. The user rejected plastic-looking tinted panels, oversized pills, repeated titles and sparse form-like main screens. The supplied reading-cat icon remains the identity asset.

The visual world comes from that icon: kinari washi paper, sumi ink, matcha leaves, sakura petals and the warm light of a shoji window. Native navigation and controls keep the app familiar on iPhone; the icon's materials own the ground, ink, tint and type beneath them. The main screens have one system large title; content supplies the second level of hierarchy. Light and dark appearances follow the device, as reading happens in changing ambient light.

## Colors

Light/dark pairs are listed above and defined once in `Theme`. Washi paper is the ground of every screen; grouped lists sit on a deeper paper with lighter paper rows. Sumi ink is the text color, usuzumi (diluted ink) the secondary. Matcha is the single interactive tint: tab selection, links, toggles, resume actions. Shu vermilion marks errors and the reading-position bookmark only. Sakura wash is the one highlight. Focused custom primary actions invert ink on paper, like a brushstroke. Color never repaints the original PDF. All text pairs meet WCAG AA in both appearances (ink ≥11.9:1, usuzumi ≥4.68:1, matcha ≥5.28:1, shu ≥4.84:1).

**The Content First Rule.** Color identifies selection or action; it does not tint reading pages or ordinary library rows.

## Typography

Two voices. **Book voice** (`.literary`): New York for Latin cascading to Hiragino Mincho for kana and kanji. It sets navigation titles, empty-state headlines, featured passages, recent-source previews, the reader's focus and neighbor lines, dictionary headwords (Title 2, W6) and focus words on review cards, word sheets and lists. SwiftUI's `design: .serif` alone falls back to gothic for Japanese, so never use it for original text. **Interface voice**: SF for labels, metadata, controls and translations.

Original Japanese text is always Mincho. Interface copy uses Mincho only when the interface language isn't Simplified Chinese; Hiragino Mincho lacks simplified glyphs and mixed faces look broken, so Chinese interface copy keeps the system fallback. Original PDF typography belongs to the document.

Keep all type responsive to the learner's system preference. Line limits summarize previews; opening the source exposes the full text. Do not reduce accessibility sizes to reproduce a default-size screenshot.

## Layout

Primary content shares a 24pt inset and a 720pt maximum width. System large titles collapse with scroll where the system owns the scroll relationship. Repeated branding and explanatory page subtitles are absent from the main destinations.

Read promotes a current original passage, its source and a resume action before recent source previews. Empty Read exposes import types directly. Documents use actual first-page thumbnails in an adaptive grid, with a minimum cell width of 156pt normally. Accessibility sizes switch to single-column rows with a small 64×88pt cover beside the complete title and page position. Dictionary places search and native segmented selection directly below navigation, followed by word-led rows. Coach combines language/stage in one menu within the scrolling content; the introduction and editable starters scroll above a safe-area input composer. Configuration does not pin a large text block above that scroll area.

## Elevation & Depth

Ordinary content is flat, with separators for structure. Glass belongs to system tabs, sheets and native presentations. Document covers alone use layered soft black shadows with nonzero downward offsets to distinguish the page edge on both appearances. Main toolbar glyphs retain their isolated, background-hidden treatment. No faux glass cards, colored halos or decorative panel borders.

## Shapes

Custom focused-task buttons use the action radius above; search uses the smaller radius; the composer uses the softer radius. Document pages have almost square corners. System tabs, segmented controls, menus, alerts and sheets own their native geometry.

## Components

- `SectionLabel`: Mincho headline followed by `InkRule`, a hairline ending in a small shu dot, like a brushstroke trailing off. Used for library section headers.
- Reading bookmark: a shu `bookmark.fill` (shiori) beside the featured passage's position metadata, shown only when lines exist.
- Toolbar glyphs are sumi ink and background-hidden; matcha is reserved for actions inside content and tab selection.
- `SourceAction`: a direct import row, SF Symbol, title, short explanation and directional arrow. Full row is tappable, minimum 44pt, with a structural bottom divider.
- Library discovery: native collapsible title search on Read and Documents. Matching is localized and title-only; whitespace-only queries behave as empty. Native menus offer persisted newest/title ordering with natural localized title comparison. Search shows all matching materials without the featured excerpt. No-result state offers a clear-search action. Read promotes the last opened material independently of sorting; Documents' options menu offers Continue reading for the last opened PDF. Deleted IDs fall back safely to existing content.
- Featured reading: Mincho original-text excerpt, source title, bookmarked language/position metadata and a matcha resume action. One target opens the existing native reader; swipe delete remains available.
- Document cover: actual PDF first page, title and page position. Thumbnail rendering runs off the main thread and is retained for the lifetime of the view. Shadow follows the fitted page, including landscape pages; unavailable previews use a semantic placeholder. Tap opens the existing document reader; context menu and accessibility action expose Delete with the existing confirmation.
- Dictionary row: prominent word and compact reading share a baseline when possible; narrow layouts stack. Meaning follows, source recedes. Zero timestamps are omitted.
- Coach starter: fills the composer for editing, without sending until the user presses Send. Language and stage share a menu with AI information. The input grows to five lines at standard sizes and two visible lines at accessibility sizes, retaining the full editable text; send starts with a 32pt visible circle inside a 44pt target, and both grow with Dynamic Type.
- Live Coach: waveform action beside the existing composer opens a focused voice sheet. Original audio is streamed only after Start. Native controls expose mute, interrupt and end; status and captions carry the conversation. No decorative waveform or invented acoustic scores. Pronunciation practice is chosen before starting, voice settings remain separate from text AI, and supported-model web search is opt-in. Backgrounding or leaving ends the session.
- Quick dictionary: a direct lookup action in Dictionary and message-level Coach lookup share one sheet. Tapping context words fills the query. Saved vocabulary and word lists appear before a new AI definition. Only Add to dictionary persists a word; existing words show a disabled saved state. Local language-aware search is available offline.
- `CompactActionStyle` / `InkButtonStyle`: intrinsic or full-width focused-task primary actions with ink/background inversion. Disabled state uses semantic secondary label/fill.
- Bilingual reader motion (`ReaderMotion.swift`), one decelerating curve `(0.16, 1, 0.3, 1)` and no bounce:
  - Ink settles: adjacent line steps move every line with the reading direction. The outgoing focus line clears in 120ms; the incoming one rises 22pt, scales from 0.97 and darkens over 500ms after an 80ms delay, so two focus lines never overlap. Context lines fade and drift 12–16pt. Seeks and jumps of more than one line cut without animation.
  - Translation has three per-session modes: Off, Tap to reveal and Always show. Translation still starts only when the learner chooses a mode, because it uses their AI service. Tap to reveal shows the gloss frosted (5pt blur, 60% opacity) with a matcha "Tap to check the meaning" prompt; a tap lifts it in 420ms and a second tap restores it. Each new line re-veils. VoiceOver hears "Translation hidden" plus a hint, never the hidden text.
  - Spoken stroke: for media, a 2pt matcha hairline over a separator track fills under the focus line as it is spoken (30fps timeline, paused with playback), for shadowing and pacing.
  - Furigana toggles cross-fade; the line counter rolls numerically; manual steps give selection haptics and reveals a light impact.
  - Reduce Motion: 200ms cross-fades only, no offset, scale or blur motion. The spoken stroke stays because it is functional.
- Press feedback: 0.96 scale and 150ms curve `(0.2, 0, 0, 1)`. Reduce Motion removes scaling. Native navigation transitions remain system-owned.
- Text reader: native bottom toolbar exposes current line and previous/next line actions for sources without media, with boundary actions disabled. Reader hides the root tabs while focused. Featured-library accessibility identifier belongs to the button, not its child texts. Source-jump requests are consumed after reaching the target so Back returns to the library.
- PDF position: restore the clamped saved page after PDFKit's initial layout, ignoring its initialization page notifications until restoration finishes. Opening a document refreshes page count and corrects obsolete positions.
- PDF translation: scrollable native sheet; selected text triggers translation while the PDF retains exact fonts, images, styling, layout and zoom. Explicit highlight/underline actions save annotations.

## Do's and Don'ts

- Do use real original text, source titles and PDF covers; never invent library content or reading progress.
- Do inspect populated states, empty states, Chinese, light/dark appearance and accessibility sizes.
- Do preserve 44pt targets, system navigation, edge-swipe back and PDF text selection.
- Don't reintroduce repeated branding/title stacks, decorative green panels or giant primary pills. Matcha is a tint, never a panel fill.
- Don't use system blue, pure white or pure black grounds, or raw `.systemBackground` row backgrounds; set `listRowBackground` per row or section, since List-level settings don't carry through.
- Don't add faux washi textures, seals or Japanese motifs as decoration; the identity is carried by paper, ink, Mincho and one tint.
- Don't turn review screenshots or passing tests into a claim of user approval.

Washi-and-ink visual pass and bilingual reader motion evidence: `docs/acceptance/washi-ink/`. Latest position/recovery verification: `docs/acceptance/reading-verification.md`. Current library discovery evidence and limitations: `docs/acceptance/library-discovery.md`; preceding visual review: `docs/acceptance/library-review.md`; earlier composition pass: `docs/acceptance/content-first-library.md`. Artwork provenance: `docs/assets/reading-artwork.md`.
