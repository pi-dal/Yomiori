import SwiftUI

/// Both paths expose the same learning actions. Ruby retains the word-boundary typesetter;
/// ordinary text uses Litext's layout, selection handles, magnifier and system edit menu.
struct TappableText: View {
    let text: String, language: String, furigana: Bool
    var pointSize: CGFloat = 17
    var lineSpacing: CGFloat = 4
    var highlighted = false
    var washed: (String) -> Bool = { _ in false }
    let onTap: (String) -> Void

    var body: some View {
        if furigana && language == "ja" {
            RubyTappableText(text: text, language: language, furigana: true, pointSize: pointSize,
                            lineSpacing: lineSpacing, highlighted: highlighted, washed: washed, onTap: onTap)
        } else {
            LitextTappableText(text: text, language: language, furigana: false, pointSize: pointSize,
                              lineSpacing: lineSpacing, highlighted: highlighted, washed: washed, onTap: onTap)
        }
    }
}
