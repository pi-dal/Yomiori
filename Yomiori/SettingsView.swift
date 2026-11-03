import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("targetLang") private var target = "ja"
    @AppStorage("nativeLang") private var native = Language.deviceDefault
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var clearFailure: String?
    @AppStorage("jaDefs") private var jaDefs = false
    @AppStorage("enDefs") private var enDefs = true
    @AppStorage("reviewLimit") private var reviewLimit = 30
    @State private var exporting = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("ReadingArtwork").resizable().scaledToFill()
                            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yomiori").font(.headline)
                            Text("よみおり").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(Theme.surface)
                Section {
                    NavigationLink { LanguagesSettingsView() } label: {
                        Label("Languages", systemImage: "character.bubble")
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                Section {
                    NavigationLink { AISettingsView() } label: { Label("AI service", systemImage: "sparkles") }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                Section {
                    Toggle("Japanese definitions", isOn: $jaDefs)
                    Toggle("English definitions", isOn: $enDefs)
                    Stepper(value: $reviewLimit, in: 10...100, step: 10) { preferenceValue("Daily review limit") { Text(reviewLimit, format: .number).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink { StagePicker() } label: { preferenceValue("Learning stage") { Text(CoachStage.current.label).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink("nav.immersion") { ImmersionView() }
                    Button("Export to Anki") { exporting = true }
                } header: { Text("Learning").font(Theme.Fonts.meta.weight(.semibold)) }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                Section {
                    Button("Clear all data", role: .destructive) { confirm = true }.foregroundStyle(Theme.errorText)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                #if DEBUG
                Section("Developer tools") { Button("Load sample content") { DebugSeed.run(ctx); dismiss() }; Button("Run Coach test") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotificationCenter.default.post(name: Notification.Name("coachtest"), object: nil) } } }
                #endif
                Section { NavigationLink("Credits") { WordListCreditsView() } }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.groupedBackground).tint(Theme.accent).font(Theme.Fonts.body)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .environment(\.defaultMinListRowHeight, 44)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Theme.surface)
            .sheet(isPresented: $exporting) { ExportSheet().presentationDetents([.medium, .large]) }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .confirmationDialog("Imported content, saved words, cards, notes, and chat history will be deleted. This can't be undone.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    do { try AppDataService.clear(context: ctx); dismiss() }
                    catch { clearFailure = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't clear all data", isPresented: Binding(get: { clearFailure != nil }, set: { if !$0 { clearFailure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(clearFailure ?? "") }
        }
    }
    private func preferenceValue<Value: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(title)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            value()
        }
    }
}
