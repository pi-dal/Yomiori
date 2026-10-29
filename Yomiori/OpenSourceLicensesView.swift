import SwiftUI

struct OpenSourceLicensesView: View {
    var body: some View {
        ScrollView {
            Text(verbatim: notices)
                .font(Theme.Fonts.meta).textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .background(Theme.background).foregroundStyle(Theme.ink)
        .navigationTitle("Open source licenses").navigationBarTitleDisplayMode(.inline)
    }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return L10n.string("Couldn't load licenses.") }
        return text
    }
}
