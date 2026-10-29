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
                    NavigationLink { LanguagesSettingsView() } label: {
                        Text("Languages").frame(minHeight: 44, alignment: .leading)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    NavigationLink { AISettingsView() } label: { Text("AI service").frame(minHeight: 44) }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    Toggle("Japanese definitions", isOn: $jaDefs)
                    Toggle("English definitions", isOn: $enDefs)
                    Stepper(value: $reviewLimit, in: 10...100, step: 10) { preferenceValue("Daily review limit") { Text(reviewLimit, format: .number).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink { StagePicker() } label: { preferenceValue("Learning stage") { Text(CoachStage.current.label).foregroundStyle(Theme.textSecondary) } }
                    NavigationLink("nav.immersion") { ImmersionView() }
                    Button("Export to Anki") { exporting = true }
                } header: { Text("Learning").font(Theme.Fonts.meta.weight(.semibold)) }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                Section {
                    Button("Clear all data", role: .destructive) { confirm = true }.foregroundStyle(Theme.errorText)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                #if DEBUG
                Section("Developer tools") { Button("Load sample content") { DebugSeed.run(ctx); dismiss() }; Button("Run Coach test") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NotificationCenter.default.post(name: Notification.Name("coachtest"), object: nil) } } }
                #endif
                Section { NavigationLink("Credits") { WordListCreditsView() } }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
            }
            .listStyle(.plain).listSectionSpacing(24).scrollContentBackground(.hidden).background(Theme.background).tint(Theme.ink).font(Theme.Fonts.body)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .environment(\.defaultMinListRowHeight, 56)
            .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
            .contentMargins(.horizontal, 0, for: .scrollContent)
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
