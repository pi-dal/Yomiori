import Foundation
import UIKit

/// Anonymous usage counts through AirTraffic (PostHog capture protocol).
/// Records shapes only: which tab, which kind of action. Never content.
enum Analytics {
    private static let host = URL(string: "https://apps.air.build/traffic/capture/")!
    private static let key = ""
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "analyticsOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "analyticsOn") }
    }

    static func capture(_ event: String, _ props: [String: Any] = [:]) {
        guard enabled, !key.isEmpty else { return }
        var p = props
        p["$process_person_profile"] = false
        p["$lib"] = "kotoba-ios"
        p["$app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let body: [String: Any] = ["api_key": key, "event": event, "distinct_id": AI.installID, "properties": p,
                                   "timestamp": ISO8601DateFormatter().string(from: Date())]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var r = URLRequest(url: host, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = data
        URLSession.shared.dataTask(with: r).resume()
    }
    static func screen(_ name: String) { capture("$screen", ["$screen_name": name]) }
}
