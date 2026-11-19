import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage("targetLang") private var target = "ja"
    @AppStorage("nativeLang") private var native = Language.deviceDefault
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var clearFailure: String?
    @State private var exporting = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { LanguagesSettingsView() } label: {
                        Label("Languages", systemImage: "character.bubble")
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                Section {
                    NavigationLink { AISettingsView() } label: { Label("AI service", systemImage: "sparkles") }
                    NavigationLink { LiveSettingsView() } label: { Label("Voice service", systemImage: "waveform") }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)).listRowBackground(Theme.surface)
                // Definitions live with Languages, stage with Coach, immersion under Today → Progress.
                Section {
                    NavigationLink { StudySettingsView() } label: { Label("study.settings", systemImage: "calendar") }
                    Button { exporting = true } label: {
                        Label("Export to Anki", systemImage: "square.and.arrow.up")
                    }.buttonStyle(TextActionStyle())
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
}
