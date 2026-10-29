import SwiftUI
import SwiftData
import PDFKit

#if DEBUG
/// Debug-only sample content so the app can be checked without importing files.
enum DebugSeed {
    static let srt = """
    1
    00:00:00,300 --> 00:00:03,200
    正直、締め切りなんてどうでもいい。

    2
    00:00:03,400 --> 00:00:06,000
    今日は天気がいいですね。

    3
    00:00:06,200 --> 00:00:09,000
    私は昨日学校を行きました。

    4
    00:00:09,200 --> 00:00:12,000
    日本語の勉強は楽しいです。
    """

    static let paragraphs = [
        "日本語を勉強することは、新しい世界を知ることです。毎日少しずつ読めば、必ず上手になります。",
        "言葉は文脈の中で覚えると忘れにくいです。本や動画から、気になった言葉を集めましょう。",
        "助詞の「は」と「が」の違いは、多くの学習者にとって難しい問題です。例文をたくさん読みましょう。",
    ]

    @MainActor static func run(_ ctx: ModelContext) {
        if let mp3 = Bundle.main.url(forResource: "sample", withExtension: "mp3"), let name = try? Files.importFile(mp3) {
            let m = Material(title: "日本語の練習", mediaFile: name)
            m.isAudio = true
            m.lines = Subtitles.parse(srt)
            ctx.insert(m)
        }
        let title = "日本語の勉強"
        let name = "seed-\(UUID().uuidString.prefix(6)).pdf"
        let r = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 595))
        try? r.writePDF(to: Files.url(name)) { c in
            c.beginPage()
            let para = NSMutableParagraphStyle(); para.lineSpacing = 6
            var y: CGFloat = 50
            for p in paragraphs {
                let s = NSAttributedString(string: p, attributes: [.font: UIFont.systemFont(ofSize: 15), .paragraphStyle: para])
                let rect = s.boundingRect(with: CGSize(width: 340, height: 300), options: .usesLineFragmentOrigin, context: nil)
                s.draw(in: CGRect(x: 40, y: y, width: 340, height: rect.height))
                y += rect.height + 28
            }
        }
        let d = PDFDoc(title: title, fileName: name)
        d.pageCount = PDFDocument(url: Files.url(name))?.pageCount ?? 1
        ctx.insert(d)
    }
}
#endif
