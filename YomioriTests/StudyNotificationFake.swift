import Foundation
import UserNotifications
@testable import Yomiori

@MainActor final class FakeStudyNotifications: StudyNotificationClient {
    var allowed = true
    var pending: [String: UNNotificationRequest] = [:]
    func authorize() async throws -> Bool { allowed }
    func authorization() async -> UNAuthorizationStatus { allowed ? .authorized : .denied }
    func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }
    func remove(_ identifiers: [String]) { identifiers.forEach { pending.removeValue(forKey: $0) } }
}
