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

struct StagePicker: View {
    @AppStorage("coachStage") private var stage = CoachStage.beginner.rawValue
    var body: some View {
        List {
            Section {
                ForEach(CoachStage.allCases, id: \.self) { s in
                    Button { stage = s.rawValue } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) { Text(s.label).font(Theme.Fonts.body.weight(.semibold)); Text(s.detail).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Image(systemName: stage == s.rawValue ? "largecircle.fill.circle" : "circle")
                        }.foregroundStyle(Theme.ink).frame(minHeight: 56)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                    .accessibilityAddTraits(stage == s.rawValue ? .isSelected : [])
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
        .font(Theme.Fonts.body).foregroundStyle(Theme.ink)
        .navigationTitle("coach.stage").navigationBarTitleDisplayMode(.inline)
    }
}
