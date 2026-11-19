import SwiftUI

enum CoachStage: String, CaseIterable {
    case beginner = "Beginner", immersion = "Immersion", output = "Output"
    var label: String {
        switch self {
        case .beginner: L10n.string("coach.beginner")
        case .immersion: L10n.string("coach.immersion")
        case .output: L10n.string("coach.output")
        }
    }
    var detail: String {
        switch self {
        case .beginner: L10n.string("coach.stageBeginner")
        case .immersion: L10n.string("coach.stageImmersion")
        case .output: L10n.string("coach.stageOutput")
        }
    }
    static var current: CoachStage { CoachStage(rawValue: UserDefaults.standard.string(forKey: "coachStage") ?? "") ?? .beginner }
    var promptRule: String {
        switch self {
        case .beginner: "Stage: Beginner. Use simple words and short sentences, with the learner's native language for help."
        case .immersion: "Stage: Immersion. Reply almost entirely in the target language, using the learner's mined sentences and words naturally."
        case .output: "Stage: Output. Reply only in the target language; the learner leads the conversation. No translations."
        }
    }
}
