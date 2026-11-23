import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Query(sort: \WorkoutSession.start, order: .reverse) private var all: [WorkoutSession]
    @Query private var slots: [TrainingSlot]
    @Query private var plans: [Plan]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query private var prs: [PersonalRecord]
    @AppStorage("anchor") private var anchor = 0.0
    @AppStorage("userName") private var userName = ""
    @State private var showWeight = false
    private let cal = Calendar.current

    private var done: [WorkoutSession] { all.filter(\.finished) }
    private var open: WorkoutSession? { all.first { !$0.finished } }
    private var plan: Plan? { plans.first { $0.isActive } }
    private var upcoming: [Planned] {
        let trained = Set(done.map { cal.startOfDay(for: $0.start) })
        return Schedule.planned(slots: slots, days: plan?.sortedDays.map(\.name) ?? [], anchor: Schedule.anchorDate(anchor),
                                from: cal.startOfDay(for: .now), to: cal.date(byAdding: .day, value: 14, to: .now)!)
            .filter { !trained.contains(cal.startOfDay(for: $0.date)) }
    }
    private func dayFor(_ p: Planned) -> PlanDay? {
        guard let d = plan?.sortedDays, d.indices.contains(p.dayIndex) else { return nil }
        return d[p.dayIndex]
    }
    private var greeting: String {
        let h = cal.component(.hour, from: .now)
        return (h < 11 ? "Guten Morgen" : h < 18 ? "Guten Tag" : "Guten Abend") + (userName.isEmpty ? "" : ", \(userName)")
    }
    private var streak: Int {
        let weeks = Set(done.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        guard var cur = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
        if !weeks.contains(cur) { cur = cal.date(byAdding: .weekOfYear, value: -1, to: cur)! }
        var n = 0
        while weeks.contains(cur) { n += 1; cur = cal.date(byAdding: .weekOfYear, value: -1, to: cur)! }
        return n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.footnote.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if let open { resumeCard(open) }
                    nextCard
                    progressCard
                    HStack(spacing: 16) {
                        Stat(icon: "flame.fill", value: "\(streak)", label: "Wochen in Folge", tint: .orange)
                        Stat(icon: "checkmark.circle.fill", value: "\(done.count)", label: "Trainingseinheiten")
                    }
                    weightCard
                    statsCard
                }
                .padding(.horizontal).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .sheet(isPresented: $showWeight) { WeightSheet() }
        }
    }

    private func resumeCard(_ s: WorkoutSession) -> some View {
        Card {
            Label("Training läuft noch", systemImage: "pause.circle.fill").font(.headline).foregroundStyle(.orange)
            Text("\(s.dayName) · gestartet \(s.start.formatted(date: .omitted, time: .shortened)) Uhr · \(s.doneSets.count) Sätze erledigt").font(.subheadline)
            Button { router.session = s } label: { Label("Fortsetzen", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    @ViewBuilder private var nextCard: some View {
        if let p = upcoming.first, let day = dayFor(p) {
            let today = cal.isDateInToday(p.date)
            VStack(alignment: .leading, spacing: 10) {
                Text(today ? "HEUTE" : "NÄCHSTES TRAINING").font(.caption.bold()).opacity(0.8)
                Text(p.dayName).font(.largeTitle.bold())
                Text(today ? "Heute um \(p.date.formatted(date: .omitted, time: .shortened)) Uhr"
                           : p.date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                    .font(.subheadline)
                Text(day.sortedItems.prefix(4).compactMap { $0.exercise?.name }.joined(separator: " · ") + (day.sortedItems.count > 4 ? " …" : ""))
                    .font(.footnote).opacity(0.85)
                Button { router.session = Workout.start(day, ctx) } label: {
                    Label("Training starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                        .foregroundStyle(today ? Color.green : Color.white)
                }
                .buttonStyle(.borderedProminent).tint(today ? .white : .green).controlSize(.large)
            }
            .foregroundStyle(today ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(today ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            Card(title: "Kein Training geplant") {
                Text("Lege im Kalender deine Trainingstage und Uhrzeiten fest.").font(.subheadline).foregroundStyle(.secondary)
                Button("Trainingstage festlegen") { router.tab = 2 }.buttonStyle(.bordered)
            }
        }
    }

    private var progressCard: some View {
        let week = cal.dateInterval(of: .weekOfYear, for: .now)!
        let n = done.filter { week.contains($0.start) }.count
        let planned = max(slots.filter(\.enabled).count, 1)
        let p = min(Double(n) / Double(planned), 1)
        return Card(title: "Plan-Fortschritt") {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 10)
                    Circle().trim(from: 0, to: p).stroke(.green, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(n)/\(planned)").font(.headline.monospacedDigit())
                }
                .frame(width: 84, height: 84).animation(.easeOut, value: p)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(n) von \(planned) Trainings diese Woche").font(.subheadline.bold())
                    Text(plan?.name ?? "Kein aktiver Plan").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var weightCard: some View {
        Card(title: "Körpergewicht") {
            if let last = weights.last {
                let recent = Array(weights.suffix(30))
                let delta = last.kg - (recent.first?.kg ?? last.kg)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(last.kg.fmt).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("kg").foregroundStyle(.secondary)
                    Spacer()
                    if recent.count > 1 { Text("\(delta >= 0 ? "+" : "")\(delta.fmt) kg").font(.footnote.bold()).foregroundStyle(.secondary) }
                }
                if recent.count > 1 {
                    Chart(recent) { e in
                        LineMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).interpolationMethod(.catmullRom).foregroundStyle(.green)
                        PointMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).foregroundStyle(.green)
                    }
                    .chartYScale(domain: .automatic(includesZero: false)).frame(height: 90)
                }
            } else {
                Text("Trage dein Körpergewicht ein, um den Verlauf zu sehen.").font(.subheadline).foregroundStyle(.secondary)
            }
            Button("Gewicht eintragen", systemImage: "plus") { showWeight = true }.buttonStyle(.bordered)
        }
    }

    private var statsCard: some View {
        let vol = done.reduce(0) { $0 + $1.volume }
        let sets = done.reduce(0) { $0 + $1.doneSets.count }
        let avg = done.isEmpty ? 0 : done.reduce(0) { $0 + $1.duration } / Double(done.count)
        return Card(title: "Persönliche Statistiken") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                tile("Gesamtvolumen", vol >= 1000 ? "\((vol / 1000).fmt) t" : "\(Int(vol)) kg")
                tile("Sätze gesamt", "\(sets)")
                tile("Bestleistungen", "\(prs.count)")
                tile("Ø Dauer", done.isEmpty ? "–" : avg.minutesText)
            }
        }
    }
    private func tile(_ l: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(.title3.bold().monospacedDigit()); Text(l).font(.caption).foregroundStyle(.secondary) }
            .accessibilityElement(children: .combine)
    }
}
