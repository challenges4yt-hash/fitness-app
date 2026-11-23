import SwiftUI
import SwiftData
import Charts

struct ProgressTab: View {
    @State private var mode = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("Ansicht", selection: $mode) { Text("Überblick").tag(0); Text("Übungen").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal)
                if mode == 0 { OverviewView() } else { ExerciseListView() }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fortschritt")
            .toolbar { ToolbarItem { NavigationLink { HistoryView() } label: { Label("Verlauf", systemImage: "clock.arrow.circlepath") } } }
        }
    }
}

struct Bucket: Identifiable { let date: Date, count: Int, volume: Double; var id: Date { date } }

struct OverviewView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.finished }, sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \PersonalRecord.date, order: .reverse) private var prs: [PersonalRecord]
    @State private var perMonth = false

    private func buckets(_ comp: Calendar.Component, _ n: Int) -> [Bucket] {
        let cal = Calendar.current
        guard let cur = cal.dateInterval(of: comp, for: .now)?.start else { return [] }
        return (0..<n).reversed().compactMap { i in
            guard let s = cal.date(byAdding: comp, value: -i, to: cur), let e = cal.date(byAdding: comp, value: 1, to: s) else { return nil }
            let ss = sessions.filter { $0.start >= s && $0.start < e }
            return Bucket(date: s, count: ss.count, volume: ss.reduce(0) { $0 + $1.volume })
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card(title: "Trainingshäufigkeit (12 Wochen)") {
                    Chart(buckets(.weekOfYear, 12)) { b in
                        BarMark(x: .value("Woche", b.date, unit: .weekOfYear), y: .value("Trainings", b.count)).foregroundStyle(.green)
                    }
                    .frame(height: 150)
                }
                Card(title: "Trainingsvolumen") {
                    Picker("Zeitraum", selection: $perMonth) { Text("Wochen").tag(false); Text("Monate").tag(true) }.pickerStyle(.segmented)
                    let comp: Calendar.Component = perMonth ? .month : .weekOfYear
                    Chart(buckets(comp, perMonth ? 6 : 12)) { b in
                        BarMark(x: .value("Zeitraum", b.date, unit: comp), y: .value("kg", b.volume)).foregroundStyle(.green)
                    }
                    .frame(height: 150)
                }
                Card(title: "Körpergewicht") {
                    if weights.count > 1 {
                        Chart(weights) { e in
                            LineMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).interpolationMethod(.catmullRom).foregroundStyle(.green)
                            PointMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).foregroundStyle(.green)
                        }
                        .chartYScale(domain: .automatic(includesZero: false)).frame(height: 150)
                    } else { Text("Trage mindestens zwei Gewichte im Profil ein.").font(.subheadline).foregroundStyle(.secondary) }
                }
                Card(title: "Persönliche Bestleistungen") {
                    if prs.isEmpty { Text("Sobald du Training abschließt, erscheinen hier deine Bestleistungen.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(prs.prefix(8)) { p in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading) {
                                Text(p.name).font(.subheadline.bold())
                                Text(p.weight > 0 ? "\(p.weight.fmt) kg × \(p.reps)" : "\(p.reps)").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(p.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal).padding(.bottom, 24)
        }
    }
}

struct ExerciseListView: View {
    @Query(filter: #Predicate<SetLog> { $0.done }) private var logs: [SetLog]
    var body: some View {
        let groups = Dictionary(grouping: logs, by: \.exerciseName)
        let names = groups.keys.sorted()
        List {
            if names.isEmpty { Text("Noch keine abgeschlossenen Trainings.").foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { n in
                NavigationLink { ExerciseProgressView(name: n) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n)
                        Text("\(Set(groups[n]!.map(\.date)).count) Trainings").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ExerciseProgressView: View {
    let name: String
    @Query private var logs: [SetLog]
    @State private var days = 90
    @State private var metric = 0

    init(name: String) {
        self.name = name
        _logs = Query(filter: #Predicate<SetLog> { $0.exerciseName == name && $0.done }, sort: \SetLog.date)
    }

    struct Pt: Identifiable {
        let date: Date, sets: [SetLog]
        var id: Date { date }
        var top: Double { sets.map(\.weight).max() ?? 0 }
        var maxReps: Int { sets.map(\.reps).max() ?? 0 }
        var volume: Double { sets.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    }
    private var all: [Pt] { Dictionary(grouping: logs, by: \.date).map { Pt(date: $0.key, sets: $0.value.sorted { $0.setIndex < $1.setIndex }) }.sorted { $0.date < $1.date } }
    private var kind: Int { logs.first?.isTimed == true ? 2 : (logs.allSatisfy { $0.weight == 0 } ? 1 : 0) }   // 0 kg · 1 Wdh. · 2 Sek.
    private var unit: String { ["kg", "Wdh.", "Sek."][kind] }
    private func value(_ p: Pt) -> Double { metric == 1 && kind == 0 ? p.volume : kind == 0 ? p.top : Double(p.maxReps) }

    var body: some View {
        let cut = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let pts = all.filter { $0.date >= cut }
        List {
            Section {
                Picker("Zeitraum", selection: $days) { Text("4 W").tag(28); Text("3 M").tag(90); Text("1 J").tag(365); Text("Alles").tag(100_000) }.pickerStyle(.segmented)
                if kind == 0 { Picker("Wert", selection: $metric) { Text("Bestgewicht").tag(0); Text("Volumen").tag(1) }.pickerStyle(.segmented) }
                if pts.count > 0 {
                    Chart(pts) { p in
                        LineMark(x: .value("Datum", p.date, unit: .day), y: .value(unit, value(p))).interpolationMethod(.catmullRom).foregroundStyle(.green)
                        PointMark(x: .value("Datum", p.date, unit: .day), y: .value(unit, value(p))).foregroundStyle(.green)
                    }
                    .chartYScale(domain: .automatic(includesZero: false)).chartYAxisLabel(metric == 1 && kind == 0 ? "kg Volumen" : unit)
                    .frame(height: 200)
                } else { Text("Keine Daten im gewählten Zeitraum.").foregroundStyle(.secondary) }
            }
            if let best = logs.max(by: { $0.score < $1.score }) {
                Section("Bestleistung") {
                    Label("\(best.summary) · \(best.date.formatted(date: .abbreviated, time: .omitted))", systemImage: "trophy.fill").foregroundStyle(.orange)
                    if kind == 0, let first = all.first, all.count > 1 {
                        Text("Seit dem ersten Training: \(first.top.fmt) → \((all.last?.top ?? 0).fmt) kg").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Verlauf") {
                ForEach(all.reversed()) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.bold())
                        Text(p.sets.map(\.summary).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        if kind == 0 { Text("Volumen: \(Int(p.volume)) kg").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<WorkoutSession> { $0.finished }, sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    var body: some View {
        List {
            if sessions.isEmpty { Text("Noch keine abgeschlossenen Trainings.").foregroundStyle(.secondary) }
            ForEach(sessions) { s in
                NavigationLink { SessionDetailView(session: s) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.dayName).font(.headline)
                        Text(s.start.formatted(date: .complete, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                        Text("\(s.doneSets.count) Sätze · \(Int(s.volume)) kg · \(s.duration.minutesText)").font(.caption)
                    }
                }
            }
            .onDelete { offs in offs.forEach { ctx.delete(sessions[$0]) }; Workout.rebuildPRs(ctx); try? ctx.save() }
        }
        .navigationTitle("Trainingshistorie")
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession
    var body: some View {
        let groups = Dictionary(grouping: session.doneSets, by: \.exOrder).sorted { $0.key < $1.key }
        List {
            Section {
                LabeledContent("Datum", value: session.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Dauer", value: session.duration.minutesText)
                LabeledContent("Volumen", value: "\(Int(session.volume)) kg")
            }
            ForEach(groups, id: \.key) { g in
                Section(g.value.first?.exerciseName ?? "") {
                    ForEach(g.value.sorted { $0.setIndex < $1.setIndex }) { s in
                        HStack {
                            Text("Satz \(s.setIndex + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text(s.summary).monospacedDigit()
                            if s.isPR { Image(systemName: "trophy.fill").foregroundStyle(.orange) }
                        }
                    }
                }
            }
        }
        .navigationTitle(session.dayName).navigationBarTitleDisplayMode(.inline)
    }
}
