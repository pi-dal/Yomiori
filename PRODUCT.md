# Yomiori

Native iPhone language learning app built with SwiftUI, SwiftData and PDFKit. Readers import their own video, audio, subtitles, media links, podcast feeds and PDF documents, save vocabulary, review cards and practice with an AI coach. Interface locale and learning language are independent.

## Confirmed design commitments

The user wants Apple-native quality and Liquid Glass in appropriate native controls. They repeatedly rejected plastic-looking tinted panels, oversized pills, repeated titles, generic icon rows and sparse form-like main screens. The accepted next direction is a content-first reading library, real document covers, stronger word typography, and a quieter conversation space. The user delegated implementation after that direction was proposed.

Keep the supplied reading-cat app icon. Preserve native navigation, accessibility text sizes, light/dark appearance, imports, saved words, reviews and practice. PDF pages must keep their exact original typography and layout; selecting text opens Chinese translation without rebuilding the page.

## Daily learning

The user requested automatic daily learning and reminders. Yomiori owns the review schedule; Anki remains optional export. Prepare a bounded daily queue from due cards, saved vocabulary and a matching word list, preserve progress between sessions, and put a direct start action on Read. Saving a word can create a review card automatically. Reminders require explicit system permission and use a configurable local time; completed work suppresses the current day's pending notification. Do not silently request additional AI enrichment to prepare the queue. The daily learning entry also exposes a learning path built from real activity: review due words, actively or passively immerse in learner-chosen material, keep a useful discovery, and optionally use Coach for expression. The path shows the next actionable step, a four-phase roadmap (foundation, understanding, expression, expansion) and behavior-based milestones. It must encourage sustainable return and tolerate missed days; it must not invent scores, proficiency or streak rewards. Daily and free practice share one guided word loop: learn from the original sentence and audio, reveal the meaning, complete a small active-recall check, then give memory feedback. The current word book is an explicit plan choice with its own title, language, entry count and learned progress; daily new-word preparation uses that book when selected, while saved words remain an optional automatic source. Daily practice applies the SRS schedule and budget; free practice includes every card for the active language, carries the same word-level and state labels, and advances through the guided loop without changing the schedule.

## Boundaries

Do not invent library content, progress or usage statistics. DEBUG previews use isolated synthetic fixtures. No TestFlight upload is authorized by this visual task. Simulator evidence does not establish real-device gesture quality or live AI accuracy.
