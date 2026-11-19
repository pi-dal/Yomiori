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

Read promotes a current original passage, its source and a resume action before recent source previews. Empty Read asks one question, the learning language, then exposes import types directly. Choosing English starts today's study from the bundled word book without an import. Documents use actual first-page thumbnails in an adaptive grid, with a minimum cell width of 156pt normally. Accessibility sizes switch to single-column rows with a small 64×88pt cover beside the complete title and page position. Dictionary places search and native segmented selection (Words, Cards, Lists) directly below navigation, with one toolbar control (ordering on Words; Lists bring their own import), followed by word-led rows. Coach combines language/stage in one menu within the scrolling content; the introduction and editable starters scroll above a safe-area input composer. Configuration does not pin a large text block above that scroll area.

## Elevation & Depth

Ordinary content is flat, with separators for structure. Glass belongs to system tabs, sheets and native presentations. Document covers alone use layered soft black shadows with nonzero downward offsets to distinguish the page edge on both appearances. Main toolbar glyphs retain their isolated, background-hidden treatment. No faux glass cards, colored halos or decorative panel borders.

## Shapes

Custom focused-task buttons use the action radius above; search uses the smaller radius; the composer uses the softer radius. Document pages have almost square corners. System tabs, segmented controls, menus, alerts and sheets own their native geometry.

## Components

- Daily learning: Read exposes Today’s study before the library. One start action opens the available review queue directly; the completion screen offers saved-position reading and a reminder opt-in. Default daily budget is 30 completed cards with at most 5 new words, old cards first. English new words use their CEFR level; the default floor is B1 and daily settings can choose a different minimum or all levels. Above the floor, new words arrive easiest first (more senses and collocations rank as more common within a level) and start where the learner's reviews suggest about 80% recall, so difficulty climbs by small daily steps rather than jumping between levels. Counts persist across sessions. Daily settings own language, source, limits, automatic saved-word cards and local reminder time. Use existing paper/ink surfaces and native list controls, with no separate dashboard or decorative progress rings.
- `SectionLabel`: Mincho headline followed by `InkRule`, a hairline ending in a small shu dot, like a brushstroke trailing off. Used for library section headers.
- Reading bookmark: a shu `bookmark.fill` (shiori) beside the featured passage's position metadata, shown only when lines exist.
- Toolbar glyphs are sumi ink and background-hidden; matcha is reserved for actions inside content and tab selection.
- `SourceAction`: a direct import row, SF Symbol, title, short explanation and directional arrow. Full row is tappable, minimum 44pt, with a structural bottom divider.
- Library discovery: native collapsible title search on Read and Documents. Matching is localized and title-only; whitespace-only queries behave as empty. Native menus offer persisted newest/title ordering with natural localized title comparison. Search shows all matching materials without the featured excerpt. No-result state offers a clear-search action. Read promotes the last opened material independently of sorting; Documents' options menu offers Continue reading for the last opened PDF. Deleted IDs fall back safely to existing content.
- Featured reading: Mincho original-text excerpt, source title, bookmarked language/position metadata and a matcha resume action. One target opens the existing native reader; swipe delete remains available.
- Document cover: actual PDF first page, title and page position. Thumbnail rendering runs off the main thread and is retained for the lifetime of the view. Shadow follows the fitted page, including landscape pages; unavailable previews use a semantic placeholder. Tap opens the existing document reader; context menu and accessibility action expose Delete with the existing confirmation.
- Dictionary row: prominent word and compact reading share a baseline when possible; narrow layouts stack. Meaning follows, source recedes. Zero timestamps are omitted.
- Coach starter: fills the composer for editing, without sending until the user presses Send. Language, stage (each with its one-line explanation) and AI information share one menu; Clear chat sits at its end behind a confirmation. The empty state is the headline and three starters; voice lives only in the composer's waveform, Weaknesses only in the toolbar. The input grows to five lines at standard sizes and two visible lines at accessibility sizes, retaining the full editable text; send starts with a 32pt visible circle inside a 44pt target, and both grow with Dynamic Type.
- Learning path: Read keeps a compact today summary and opens Today. Today's first screen is one status line, one primary action and a quiet checklist of review, active/passive immersion, one saved discovery and optional expression; it chooses one next action from actual data. Free practice and Progress follow as single rows; daily settings sit in the toolbar; the reminder opt-in appears only once the day's review is done. Progress, one level down, holds four plain counts and the immersion log: no tiers, phases, points, progress rings or forced streak language. On Read, the "Today's study" heading itself opens Today, with one start action beneath it; the block is absent until any card exists.
- Word books: Daily settings present the selected word list as a current word book with its title, language, entry count and learned progress. Automatic selection remains available for a low-decision start; a specific book constrains new-word preparation, while saved words can still be enabled as an automatic source.
- Free practice: Daily review keeps its SRS budget and rating actions. Both modes use the same guided loop: original sentence and audio first, meaning reveal second, active-recall choices third, and memory feedback last. Free practice reads every current-language card in due/new/scheduled order, shows the same level and state labels, and never changes scheduling.

- Live Coach: waveform action beside the existing composer opens a focused voice sheet. Original audio is streamed only after Start. Native controls expose mute, interrupt and end; status and captions carry the conversation. No decorative waveform or invented acoustic scores. Pronunciation practice is chosen before starting, voice settings remain separate from text AI, and supported-model web search is opt-in. Backgrounding or leaving ends the session.
- Quick dictionary: a direct lookup action in Dictionary and lookup on Coach replies share one sheet. Tapping context words fills the query. Saved vocabulary and word lists appear before a new AI definition. Only Add to dictionary persists a word; existing words show a disabled saved state. Local language-aware search is available offline.
- Action hierarchy: `CompactActionStyle` / `InkButtonStyle` share one primary treatment (intrinsic/full width): ink/background inversion, 10pt continuous corners, 48pt minimum height, wrapping SF semibold labels and 18pt horizontal / 13pt vertical insets. `PaperActionStyle` uses a deeper paper fill with matcha labels for secondary commands; destructive roles retain vermilion and disabled controls use usuzumi. `TextActionStyle` provides matcha inline actions and 44pt targets. `ActionRowLabel` aligns a Dynamic Type-sized SF Symbol, title, optional source detail and quiet disclosure chevron. Navigation toolbars, menus, pickers and alerts retain native presentation. Review ratings use equal paper actions with next intervals; no default rating is visually preselected. Recall answers use `AnswerChoiceStyle`: leading-aligned body-size ink text on the paper fill, one sense per answer, because they are read and compared rather than pressed as commands. No decorative control borders or shadows.
- Bilingual reader motion (`ReaderMotion.swift`), one decelerating curve `(0.16, 1, 0.3, 1)` and no bounce:
  - Ink settles: adjacent line steps move every line with the reading direction. The outgoing focus line clears in 120ms; the incoming one rises 22pt, scales from 0.97 and darkens over 500ms after an 80ms delay, so two focus lines never overlap. Context lines fade and drift 12–16pt. Seeks and jumps of more than one line cut without animation.
  - Translation has three per-session modes: Off, Tap to reveal and Always show. Translation still starts only when the learner chooses a mode, because it uses their AI service. Tap to reveal shows the gloss frosted (5pt blur, 60% opacity) with a matcha "Tap to check the meaning" prompt; a tap lifts it in 420ms and a second tap restores it. Each new line re-veils. VoiceOver hears "Translation hidden" plus a hint, never the hidden text.
  - Spoken stroke: for media, a 2pt matcha hairline over a separator track fills under the focus line as it is spoken (30fps timeline, paused with playback), for shadowing and pacing.
  - Furigana toggles cross-fade; the line counter rolls numerically; manual steps give selection haptics and reveals a light impact.
  - Reduce Motion: 200ms cross-fades only, no offset, scale or blur motion. The spoken stroke stays because it is functional.
- Press feedback: primary and paper actions settle to 0.985 scale over 150ms; paper actions deepen their fill and text commands reduce opacity. Disabled controls do not react to presses. Reduce Motion removes scaling. Native navigation transitions remain system-owned.
- Ink moments ("the ink remembers"): acknowledgement comes only from real actions and scheduler data, using marks the app already owns. No confetti, sounds, points or streaks.
  - Graded choices: after a recall answer the choices keep their place. The meaning is inked matcha and semibold with a drawn checkmark; a wrong pick is struck in shu with a drawn ✕, like Coach corrections; the rest fade to 40%. The verdict replaces the question line, and answer details skip the meaning already shown. VoiceOver reads "Correct answer" / "Your choice, not correct".
  - Study stroke in the word sheet: once a word has a card, the reader's stroke (2pt matcha learning, 1pt faint ink known) sits under it in the observed sentence via `BrushStrokeRenderer`, one span per line. Saving draws it left to right over 600ms; Reduce Motion fades it.
  - A word that sticks: when a daily rating carries a card from learning to a ≥21-day interval, "<word> has stuck" with a matcha seal appears beside the progress count for 2.8s, with a VoiceOver announcement.
  - Page of words: the session summary sets every word met in Mincho, recalled in ink, words to revisit in usuzumi regular, stuck words sealed; they settle in with a 60ms stagger (capped). Stats become a caption.
  - Waiting: lookups show a breathing redacted meaning placeholder; Coach shows "Coach is writing…". Reduce Motion keeps them static.
  - Haptics, one vocabulary (`SensoryFeedback.ink*` / `Haptic`): step (selection) for line steps and misses; reveal (soft impact) for veils, correct recall and highlights; kept (success) only for saved words, cards, a word that stuck or the session's last card.
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

Ink moments evidence: `docs/acceptance/ink-moments.md`. Washi-and-ink visual pass and bilingual reader motion evidence: `docs/acceptance/washi-ink/`. Latest position/recovery verification: `docs/acceptance/reading-verification.md`. Current library discovery evidence and limitations: `docs/acceptance/library-discovery.md`; preceding visual review: `docs/acceptance/library-review.md`; earlier composition pass: `docs/acceptance/content-first-library.md`. Artwork provenance: `docs/assets/reading-artwork.md`.
