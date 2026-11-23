import SwiftUI
import SwiftData
import UserNotifications

struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @State private var restEnd: Date?
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

    private var groups: [[SetLog]] {
        Dictionary(grouping: session.sets, by: \.exOrder).sorted { $0.key < $1.key }.map { $0.value.sorted { $0.setIndex < $1.setIndex } }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.finished { SummaryView(session: session) { router.session = nil } } else { active }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(session.finished ? "Zusammenfassung" : session.dayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var active: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Label { Text(session.start, style: .timer).monospacedDigit() } icon: { Image(systemName: "timer") }
                    Spacer()
                    Text("\(session.doneSets.count)/\(session.sets.count) Sätze").foregroundStyle(.secondary)
                }
                .font(.headline)
                ForEach(groups.indices, id: \.self) { i in
                    ExerciseCard(sets: groups[i], onToggle: toggled, onAdd: { addSet(groups[i]) })
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { restBar }
        .task(id: restEnd) {
            guard let end = restEnd else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
            if !Task.isCancelled { restEnd = nil }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Später fortsetzen") { router.session = nil }
                    Button("Training verwerfen", role: .destructive) { confirmDiscard = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Beenden") { confirmFinish = true }.bold() }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .confirmationDialog("Training beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Beenden und speichern") { finish() }
            Button("Weitermachen", role: .cancel) {}
        } message: { Text("Nicht abgehakte Sätze werden nicht gespeichert.") }
        .alert("Training verwerfen?", isPresented: $confirmDiscard) {
            Button("Verwerfen", role: .destructive) { setRest(nil); Workout.discard(session, ctx); router.session = nil }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Alle Eingaben dieses Trainings gehen verloren.") }
    }

    @ViewBuilder private var restBar: some View {
        if let end = restEnd {
            let now = Date.now
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                Text("Pause").font(.headline)
                Text(timerInterval: now...max(end, now), countsDown: true, showsHours: false).font(.title3.bold().monospacedDigit())
                Spacer()
                Button("+15 s") { setRest(end.addingTimeInterval(15)) }
                Button("Skip") { setRest(nil) }.bold()
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal).padding(.bottom, 4)
        }
    }

    private func setRest(_ end: Date?) {
        restEnd = end
        if let end { Task { await Notifier.rest(in: end.timeIntervalSinceNow) } }
        else { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"]) }
    }

    private func toggled(_ s: SetLog) {
        try? ctx.save()
        if s.done { setRest(.now.addingTimeInterval(TimeInterval(s.rest))) }
    }

    private func addSet(_ g: [SetLog]) {
        guard let l = g.last else { return }
        let n = SetLog(name: l.exerciseName, muscle: l.muscle, exOrder: l.exOrder, setIndex: l.setIndex + 1, weight: l.weight, reps: l.reps,
                       bw: l.isBodyweight, timed: l.isTimed, repMin: l.repMin, repMax: l.repMax, rest: l.rest, date: l.date)
        ctx.insert(n); n.session = session
    }

    private func finish() {
        if session.doneSets.isEmpty { Workout.discard(session, ctx); router.session = nil; return }
        setRest(nil)
        Workout.finish(session, ctx)
        Task { await Notifier.refresh(ctx) }
    }
}

struct ExerciseCard: View {
    let sets: [SetLog]
    let onToggle: (SetLog) -> Void
    let onAdd: () -> Void

    var body: some View {
        let f = sets[0]
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.exerciseName).font(.title3.bold())
                Text("\(f.repMin)–\(f.repMax) \(f.isTimed ? "Sek." : "Wdh.") · \(f.muscle)" + (f.isBodyweight && !f.isTimed ? " · Zusatzgewicht optional" : ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if f.suggested > 0 {
                Button { sets.filter { !$0.done }.forEach { $0.weight = f.suggested } } label: {
                    Label("Alle Wiederholungen erreicht – auf \(f.suggested.fmt) kg steigern", systemImage: "arrow.up.circle.fill").font(.footnote)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            ForEach(sets) { s in SetRow(s: s, onToggle: onToggle) }
            Button("Satz hinzufügen", systemImage: "plus", action: onAdd).font(.footnote)
        }
    }
}

struct SetRow: View {
    @Bindable var s: SetLog
    let onToggle: (SetLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("\(s.setIndex + 1)").font(.subheadline.bold()).frame(width: 26, height: 26).background(Color(.tertiarySystemFill), in: Circle())
                if !s.isTimed {
                    TextField("kg", value: $s.weight, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad).field()
                        .accessibilityLabel("Gewicht Satz \(s.setIndex + 1)")
                    Text("×").foregroundStyle(.secondary)
                }
                TextField(s.isTimed ? "Sek." : "Wdh.", value: $s.reps, format: .number).keyboardType(.numberPad).field()
                    .accessibilityLabel(s.isTimed ? "Sekunden Satz \(s.setIndex + 1)" : "Wiederholungen Satz \(s.setIndex + 1)")
                Spacer(minLength: 0)
                Button { s.done.toggle(); onToggle(s) } label: {
                    Image(systemName: s.done ? "checkmark.circle.fill" : "circle").font(.title).foregroundStyle(s.done ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain).sensoryFeedback(.success, trigger: s.done)
                .accessibilityLabel("Satz \(s.setIndex + 1) \(s.done ? "abgeschlossen" : "offen")")
            }
            if s.prevReps > 0 {
                Text("Zuletzt: " + (s.isTimed ? "\(s.prevReps) Sek." : s.prevWeight > 0 ? "\(s.prevWeight.fmt) kg × \(s.prevReps)" : "\(s.prevReps) Wdh."))
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 36)
            }
        }
    }
}

struct SummaryView: View {
    let session: WorkoutSession
    let close: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(.green).padding(.top, 12)
                Text("Training abgeschlossen").font(.title.bold())
                Text(session.dayName).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    Stat(icon: "timer", value: session.duration.minutesText, label: "Dauer")
                    Stat(icon: "list.bullet", value: "\(session.exerciseCount)", label: "Übungen")
                    Stat(icon: "square.stack.3d.up.fill", value: "\(session.doneSets.count)", label: "Sätze")
                    Stat(icon: "scalemass.fill", value: "\(Int(session.volume)) kg", label: "Volumen")
                }
                let prs = session.doneSets.filter(\.isPR)
                if !prs.isEmpty {
                    Card(title: "Neue Bestleistungen") {
                        ForEach(prs) { Label("\($0.exerciseName): \($0.summary)", systemImage: "trophy.fill").foregroundStyle(.orange) }
                    }
                }
                Button(action: close) { Text("Fertig").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            .padding()
        }
    }
}
