// AppFeedback.swift — an in-app feedback form. What the person writes,
// plus up to four photos, goes to this application's independent platform environment.
//
// Copy this file into the app target unchanged except for
// `FeedbackConfig.endpoint` and `FeedbackConfig.appKey`. Requires no packages, no Info.plist entries, and
// no account: a public ingestion key authorizes submission only. iOS 17 or later.
//
// Usage — present the form from anywhere:
//   .sheet(isPresented: $showFeedback) { FeedbackView() }
// or send without the form:
//   try await FeedbackClient.send(message: "…", images: [uiImage])
//
// The form's strings are plain English; localize them like the rest of the
// app if the app is localized.

import PhotosUI
import SwiftUI
import UIKit

enum FeedbackConfig {
    /// The `feedbackEndpoint` and public `key` returned by `workers app-key`.
    static let endpoint = URL(string: "https://apps.air.build/v1/ingest/feedback")!
    static let appKey = ""
    static let maximumImages = 4
}

enum FeedbackClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Sends one piece of feedback. Images are downscaled to 2048 px on the
    /// long side and sent as JPEG, so a report with four screenshots stays
    /// small enough for cellular. Main actor because the device strings come
    /// from `UIDevice`; the network wait does not block anything.
    @MainActor
    static func send(message: String, images: [UIImage]) async throws {
        guard !FeedbackConfig.appKey.isEmpty else {
            throw Failure(message: "Configure your feedback service before sending.")
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let body: [String: Any] = [
            "message": message,
            "appVersion": info["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": info["CFBundleVersion"] as? String ?? "",
            "deviceModel": deviceModel,
            "osVersion": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            "locale": Locale.current.identifier,
            "images": images.prefix(FeedbackConfig.maximumImages).compactMap { image -> [String: String]? in
                guard let data = jpegData(image) else { return nil }
                return ["mediaType": "image/jpeg", "data": data.base64EncodedString()]
            },
        ]

        var request = URLRequest(url: FeedbackConfig.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(FeedbackConfig.appKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure(message: L10n.string("Couldn't send feedback. Try again."))
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Failure(message: L10n.string("Couldn't send feedback. Try again."))
        }
    }

    private static func jpegData(_ image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: 0.8)
    }

    /// The hardware identifier (`iPhone17,2`), which is what a bug report needs;
    /// `UIDevice.model` only says "iPhone".
    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var sending = false
    @State private var failure: String?
    @State private var sent = false

    private var canSend: Bool {
        !sending && (!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                Section {
                    TextField("Feedback", text: $message, axis: .vertical)
                        .lineLimit(5 ... 12)
                        .padding(12)
                        .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                }
                Section {
                    if !images.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(images.indices, id: \.self) { index in
                                    Image(uiImage: images[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                images.remove(at: index)
                                                pickerItems = []
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(Theme.background, Theme.ink)
                                                    .font(.system(size: 20))
                                                    .frame(width: 44, height: 44)
                                            }
                                            .accessibilityLabel("Remove screenshot")
                                        }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: FeedbackConfig.maximumImages - images.count,
                        matching: .images
                    ) {
                        Label("Add screenshots", systemImage: "photo.on.rectangle")
                    }
                    .disabled(images.count >= FeedbackConfig.maximumImages)
                    Text(L10n.format("feedback.limit", Int64(FeedbackConfig.maximumImages))).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                    DisclosureGroup("Details") { Text("Includes app version and device model.").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                }
                if let failure {
                    Section {
                        Text(failure).foregroundStyle(Theme.errorText)
                    }
                }
            }
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden).background(Theme.background)
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send") { send() }.disabled(!canSend)
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await load(items) }
            }
            .alert("Feedback sent", isPresented: $sent) {
                Button("Done") { dismiss() }
            }
            .interactiveDismissDisabled(sending)
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard images.count < FeedbackConfig.maximumImages,
                  let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            images.append(image)
        }
        pickerItems = []
    }

    private func send() {
        sending = true
        failure = nil
        Task {
            do {
                try await FeedbackClient.send(message: message, images: images)
                sent = true
            } catch {
                failure = L10n.string("Couldn't send feedback. Try again.")
            }
            sending = false
        }
    }
}
