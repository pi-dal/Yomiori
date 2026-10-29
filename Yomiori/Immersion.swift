import SwiftUI
import SwiftData
import Charts

@Model final class ImmersionLog {
    var day: Date
    var seconds: Double
    var kind: String   // listening | reading | manual
    var note: String = ""
    init(day: Date, seconds: Double, kind: String) { self.day = day; self.seconds = seconds; self.kind = kind }
}

enum Immersion {
    @MainActor static func add(_ ctx: ModelContext, seconds: Double, kind: String) {
        let day = Calendar.current.startOfDay(for: Date())
        let logs = (try? ctx.fetch(FetchDescriptor<ImmersionLog>(predicate: #Predicate { $0.day == day && $0.kind == kind }))) ?? []
        if let l = logs.first(where: { $0.note.isEmpty }) { l.seconds += seconds } else { ctx.insert(ImmersionLog(day: day, seconds: seconds, kind: kind)) }
    }
    static func format(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? L10n.format("%lld hr %lld min", Int64(m / 60), Int64(m % 60)) : L10n.format("review.nextMinutes", Int64(m))
    }
}

struct ImmersionView: View {
    @Query private var logs: [ImmersionLog]
    @Query private var entries: [DictEntry]
    @Query private var cards: [Card]
    @Environment(\.modelContext) private var ctx
    @AppStorage("dailyGoal") private var goal = 60
    @State private var adding = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var cal: Calendar { .current }
    private func total(_ ls: [ImmersionLog]) -> Double { ls.reduce(0) { $0 + $1.seconds } }
    private var today: Double { total(logs.filter { cal.isDateInToday($0.day) }) }
    private var days: [(day: Date, secs: Double)] {
        (0..<7).reversed().map { off in
            let d = cal.startOfDay(for: cal.date(byAdding: .day, value: -off, to: Date())!)
            return (d, total(logs.filter { $0.day == d }))
        }
    }
    private var streak: Int {
        var n = 0, d = cal.startOfDay(for: Date())
        if total(logs.filter { $0.day == d }) == 0 { d = cal.date(byAdding: .day, value: -1, to: d)! }
        while total(logs.filter { $0.day == d }) > 0 { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }
    private var mined: Int { Set(cards.map(\.word) + entries.filter { $0.kind == "word" }.map(\.term)).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if logs.isEmpty { Text("No time recorded").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary) }
                VStack(alignment: .leading, spacing: 0) {
                    row("Today", Immersion.format(today))
                    row("Total", Immersion.format(total(logs)))
                    row("Streak", streak.formatted())
                    row("Words mined", mined.formatted())
                }
                VStack(alignment: .leading, spacing: 8) {
                    row("This week", Immersion.format(days.reduce(0) { $0 + $1.secs }))
                    Chart(days, id: \.day) { d in
                        BarMark(x: .value(L10n.string("Day"), d.day, unit: .day), y: .value(L10n.string("Minutes"), d.secs / 60))
                            .foregroundStyle(Theme.ink)
                            .accessibilityLabel(d.day.formatted(.dateTime.weekday(.wide))).accessibilityValue(Immersion.format(d.secs))
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)).font(Theme.Fonts.meta) } }
                    .chartYAxis(.hidden).frame(height: 90)
                }
                VStack(spacing: 0) {
                    row("Listening", Immersion.format(total(logs.filter { $0.kind == "listening" })))
                    row("Reading", Immersion.format(total(logs.filter { $0.kind == "reading" })))
                    HStack {
                        Stepper(value: $goal, in: 15...240, step: 15) { VStack(alignment: .leading, spacing: 8) { Text("Daily goal"); Text(L10n.format("review.nextMinutes", Int64(goal))).foregroundStyle(Theme.textSecondary) } }
                    }.padding(.vertical, 12)
                    if today >= Double(goal * 60) { Text("Daily goal reached").font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("History").font(Theme.Fonts.body.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    ForEach(logs.sorted { $0.day > $1.day }) { log in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(log.note.isEmpty ? L10n.string(log.kind == "listening" ? "Listening" : log.kind == "reading" ? "Reading" : "Activity") : log.note)
                                .font(Theme.Fonts.body)
                            Text(log.day, format: .dateTime.year().month().day())
                                .font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                            Text(Immersion.format(log.seconds)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                }
                Button { adding = true } label: { Text("Add time") }.buttonStyle(InkButtonStyle())
            }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
        }
        .background(Theme.background).font(Theme.Fonts.body).foregroundStyle(Theme.ink)
        .navigationTitle("nav.immersion").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("Add time")
        } }
        .sheet(isPresented: $adding) { AddTimeSheet().presentationDetents([.medium, .large]) }
    }
    private func row(_ l: String, _ v: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(L10n.string(l)).font(Theme.Fonts.meta).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(v).font(Theme.Fonts.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

}

struct AddTimeSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = ""
    @State private var what = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minutes")
                        TextField("", text: $minutes).accessibilityLabel("Minutes").keyboardType(.numberPad)
                            .padding(.horizontal, 12).frame(minHeight: 48)
                            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity")
                        TextField("", text: $what, axis: .vertical).accessibilityLabel("Activity")
                            .padding(.horizontal, 12).padding(.vertical, 12).frame(minHeight: 48)
                            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxWidth: 720, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden).background(Theme.background).font(Theme.Fonts.body).foregroundStyle(Theme.ink)
            .navigationTitle("Add time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add time") {
                        if let m = Double(minutes), m > 0 { let l = ImmersionLog(day: Calendar.current.startOfDay(for: Date()), seconds: m * 60, kind: "manual"); l.note = what; ctx.insert(l) }
                        dismiss()
                    }.disabled((Double(minutes) ?? 0) <= 0)
                }
            }
        }
    }
}

/// Counts time while it is on screen and `active` is true (media playing, or a document open).
struct ImmersionTicker: ViewModifier {
    @Environment(\.modelContext) private var ctx
    let kind: String
    let active: Bool
    func body(content: Content) -> some View {
        content.onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            if active { Immersion.add(ctx, seconds: 5, kind: kind) }
        }
    }
}
extension View { func immersion(_ kind: String, active: Bool) -> some View { modifier(ImmersionTicker(kind: kind, active: active)) } }
