import Foundation
import UserNotifications
import Observation

struct StudyReminderSchedule {
    /// One local notification per day. A completed day is omitted; calendar triggers follow local time.
    static func dates(now: Date, hour: Int, minute: Int, skipToday: Bool, calendar: Calendar = .current) -> [DateComponents] {
        (0..<30).compactMap { offset in
            guard !(offset == 0 && skipToday),
                  let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let date = calendar.date(bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0, of: day),
                  date > now else { return nil }
            return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
    }
}

@MainActor protocol StudyNotificationClient {
    func authorize() async throws -> Bool
    func authorization() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ identifiers: [String])
}

@MainActor private struct SystemStudyNotifications: StudyNotificationClient {
    func authorize() async throws -> Bool { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
    func authorization() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func add(_ request: UNNotificationRequest) async throws { try await UNUserNotificationCenter.current().add(request) }
    func remove(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor @Observable final class StudyReminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StudyReminders()
    var openStudy = false
    var failure: String?
    private var revision = UUID()
    private let client: any StudyNotificationClient
    private let storage: UserDefaults

    init(client: (any StudyNotificationClient)? = nil, storage: UserDefaults = .standard) {
        self.client = client ?? SystemStudyNotifications(); self.storage = storage
        super.init()
    }
    func install() { UNUserNotificationCenter.current().delegate = self }
    func handleDestination(_ destination: String?) {
        if destination == "daily-study" { openStudy = true }
    }

    func enable(defaults: UserDefaults) async {
        do {
            let granted = try await client.authorize()
            defaults.set(granted, forKey: "study.reminders")
            failure = granted ? nil : L10n.string("study.notificationsDenied")
        } catch { defaults.set(false, forKey: "study.reminders"); failure = L10n.string("study.notificationsError") }
    }

    func cancel() {
        revision = UUID()
        let ids = (storage.stringArray(forKey: "study.notificationIDs") ?? []) + (0..<30).map { "yomiori.study.\($0)" }
        client.remove(ids)
        storage.removeObject(forKey: "study.notificationIDs")
    }

    func refresh(defaults: UserDefaults, completed: Bool, now: Date = Date()) async {
        #if DEBUG
        if client is SystemStudyNotifications, ProcessInfo.processInfo.arguments.contains("--library-design-preview") { return }
        #endif
        cancel()
        guard defaults.bool(forKey: "study.reminders"), !Operations.shared.resetPending else { return }
        let token = revision
        let authorization = await client.authorization()
        guard token == revision else { return }
        guard authorization == .authorized || authorization == .provisional else {
            failure = L10n.string("study.notificationsDenied"); return
        }
        let hour = defaults.object(forKey: "study.hour") == nil ? 20 : defaults.integer(forKey: "study.hour")
        let dates = StudyReminderSchedule.dates(now: now, hour: hour, minute: defaults.integer(forKey: "study.minute"), skipToday: completed)
        failure = nil
        let identifiers = dates.indices.map { "yomiori.study.\(token.uuidString).\($0)" }
        storage.set(identifiers, forKey: "study.notificationIDs")
        for (index, date) in dates.enumerated() {
            guard token == revision else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.string("study.reminderTitle")
            content.body = L10n.string("study.reminderBody")
            content.sound = .default
            content.userInfo = ["destination": "daily-study"]
            do {
                try await client.add(UNNotificationRequest(identifier: identifiers[index], content: content,
                                                          trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)))
                if token != revision {
                    client.remove([identifiers[index]])
                    return
                }
            } catch { if token == revision { failure = L10n.string("study.notificationsError") }; return }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["destination"] as? String == "daily-study" {
            Task { @MainActor in self.handleDestination("daily-study") }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
