import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = AIConfigurationStore.shared
    @State private var configuration = AIConfiguration()
    @State private var apiKey = ""
    @State private var loaded = false
    @State private var failure: String?
    @State private var testResult: String?
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("API format", selection: $configuration.format) {
                    Text("Responses").tag(AIConfiguration.Format.responses)
                    Text("Chat Completions").tag(AIConfiguration.Format.openAI)
                    Text("Custom relay").tag(AIConfiguration.Format.relay)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint URL").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    TextField("https://api.openai.com/v1/responses", text: $configuration.endpoint, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Endpoint URL").accessibilityIdentifier("ai.endpoint")
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model name").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    TextField("Model name", text: $configuration.model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Model name").accessibilityIdentifier("ai.model")
                }.padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Text("API key (optional)").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    SecureField("API key (optional)", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("API key (optional)").accessibilityIdentifier("ai.key")
                }.padding(.vertical, 4)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter the full endpoint, including /v1/responses or /v1/chat/completions. A custom relay returns a text field.")
                    Text("Your API key is stored in Keychain on this device. Reading passages and chat messages are sent to the service you choose.")
                }.font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
            }
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }.disabled(testing || !loaded)
                if let testResult { Text(testResult).foregroundStyle(Theme.textSecondary).accessibilityAddTraits(.updatesFrequently) }
                if let failure { Text(failure).foregroundStyle(Theme.errorText).accessibilityAddTraits(.updatesFrequently) }
                if testing { Button("Cancel", role: .cancel) { cancelTest() } }
            } footer: { Text("Testing sends a short message and may incur usage charges. Changes take effect after saving.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
            if !loaded {
                Section { Button("Try again") { load() } }
            }
            Section {
                Button("Remove AI configuration", role: .destructive) { confirmReset = true }.disabled(!loaded || testing)
            }
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .foregroundStyle(Theme.ink).tint(Theme.ink).font(Theme.Fonts.body)
        .navigationTitle("AI service").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!loaded || testing)
            }
        }
        .onAppear { load() }
        .onChange(of: configuration) { _, _ in cancelTest(); testResult = nil; failure = nil }
        .onChange(of: apiKey) { _, _ in cancelTest(); testResult = nil; failure = nil }
        .onDisappear { cancelTest() }
        .confirmationDialog("Remove AI configuration?", isPresented: $confirmReset) {
            Button("Remove", role: .destructive) {
                do { try store.reset(); dismiss() } catch { failure = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func load() {
        do {
            let key = try store.apiKey()
            configuration = store.configuration; apiKey = key; loaded = true; failure = nil
        } catch { failure = error.localizedDescription; loaded = false }
    }
    private func save() {
        do { try store.save(configuration, apiKey: apiKey); dismiss() }
        catch { failure = error.localizedDescription }
    }
    private func cancelTest() { testTask?.cancel(); testTask = nil; testing = false }
    private func testConnection() {
        failure = nil; testResult = nil
        do {
            let client = try AIClient(configuration: configuration, apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            testing = true
            testTask = Task {
                defer { if !Task.isCancelled { testing = false } }
                do {
                    // Verify both paths: Coach streams while dictionary/translation use completion.
                    _ = try await client.complete([AIMessage(role: "user", content: "Reply OK.")])
                    var output = ""
                    for try await delta in client.stream([AIMessage(role: "user", content: "Reply OK.")]) { output += delta }
                    try Task.checkCancellation()
                    guard !output.isEmpty else { throw AIError.invalidResponse }
                    testResult = L10n.string("Connection successful. Completion and streaming both work.")
                } catch {
                    guard !Task.isCancelled else { return }
                    failure = error.localizedDescription
                }
            }
        } catch { failure = error.localizedDescription }
    }
}
