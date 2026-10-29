import SwiftUI

struct WordListCreditsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Word Atlas").font(Theme.Fonts.meta.weight(.semibold))
                Text("IELTS word list from Word Atlas by designfuchen, licensed under CC BY 4.0.")
                Text("Word Atlas contributors — CC BY 4.0").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Text("The dataset is bundled for offline use. JSON formatting was compacted; definitions and examples are unchanged. Media is loaded on demand from Word Atlas.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                Link("View source", destination: URL(string: "https://github.com/designfuchen/word-atlas")!).frame(minHeight: 44, alignment: .leading)
                Link("CC BY 4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!).frame(minHeight: 44, alignment: .leading)
                Text("This is not an official IELTS word list and is not affiliated with the IELTS partners.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        }
        .font(Theme.Fonts.body).foregroundStyle(Theme.ink).tint(Theme.ink)
        .listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(L10n.string("Credits")).navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguagesSettingsView: View {
    @AppStorage("targetLang") private var learning = "ja"
    @AppStorage("nativeLang") private var native = Language.deviceDefault
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning language")
                    Picker("Learning language", selection: $learning) {
                        Text("Japanese").tag("ja")
                        Text("English").tag("en")
                    }.labelsHidden().frame(minHeight: 44)
                }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Translation language")
                    Picker("Translation language", selection: $native) {
                        ForEach(Language.all) { Text($0.displayName).tag($0.code) }
                    }.labelsHidden().frame(minHeight: 44)
                }.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }.pickerStyle(.menu).frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        }
        .listStyle(.plain).listSectionSpacing(24)
        .font(Theme.Fonts.body).foregroundStyle(Theme.ink).tint(Theme.ink)
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(L10n.string("Languages")).navigationBarTitleDisplayMode(.inline)
    }
}
