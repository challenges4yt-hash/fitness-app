import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @Query(sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @Query private var slots: [TrainingSlot]
    @Query private var plans: [Plan]
    @AppStorage("anchor") private var anchor = 0.0
    @State private var month = Date.now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    private let cal = Calendar.current

    private var plan: Plan? { plans.first { $0.isActive } }
    private var trainedDays: Set<Date> { Set(sessions.filter(\.finished).map { cal.startOfDay(for: $0.start) }) }
    private func planned(_ from: Date, _ to: Date) -> [Planned] {
        Schedule.planned(slots: slots, days: plan?.sortedDays.map(\.name) ?? [], anchor: Schedule.anchorDate(anchor), from: from, to: to)
    }
    private var days: [Date?] {
        let start = cal.dateInterval(of: .month, for: month)!.start
        let count = cal.range(of: .day, in: .month, for: month)!.count
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        return [Date?](repeating: nil, count: lead) + (0..<count).map { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthCard
                    detail
                }
                .padding(.horizontal).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Kalender")
            .toolbar {
                ToolbarItem { NavigationLink { ScheduleEditor() } label: { Label("Trainingstage", systemImage: "clock.badge.checkmark") } }
            }
        }
    }

    private var monthCard: some View {
        let ms = cal.dateInterval(of: .month, for: month)!
        let plannedDays = Set(planned(ms.start, ms.end).map { cal.startOfDay(for: $0.date) })
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return Card {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Vorheriger Monat")
                Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Nächster Monat").padding(.leading, 12)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { Text(symbols[($0 + cal.firstWeekday - 1) % 7]).font(.caption.bold()).foregroundStyle(.secondary) }
                ForEach(days.indices, id: \.self) { i in
                    if let d = days[i] { cell(d, plannedDays) } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }

    private func cell(_ d: Date, _ plannedDays: Set<Date>) -> some View {
        let isSel = cal.isDate(d, inSameDayAs: selected), isToday = cal.isDateInToday(d)
        let dot: Color = trainedDays.contains(d) ? .green : plannedDays.contains(d) ? Color(.systemGray3) : .clear
        return VStack(spacing: 3) {
            Text("\(cal.component(.day, from: d))").font(.callout).fontWeight(isToday ? .bold : .regular)
                .frame(width: 34, height: 34)
                .background(isSel ? Color.green : Color.clear, in: Circle())
                .foregroundStyle(isSel ? Color.white : isToday ? Color.green : Color.primary)
            Circle().fill(dot).frame(width: 6, height: 6)
        }
        .frame(height: 44).contentShape(Rectangle())
        .onTapGesture { selected = d }
        .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (trainedDays.contains(d) ? ", Training absolviert" : plannedDays.contains(d) ? ", Training geplant" : ""))
    }

    @ViewBuilder private var detail: some View {
        let ds = sessions.filter { $0.finished && cal.isDate($0.start, inSameDayAs: selected) }
        let next = cal.date(byAdding: .day, value: 1, to: selected)!
        let ps = ds.isEmpty ? planned(selected, next).filter { cal.isDate($0.date, inSameDayAs: selected) } : []
        Card(title: selected.formatted(.dateTime.weekday(.wide).day().month(.wide))) {
            if ds.isEmpty && ps.isEmpty { Text("Kein Training an diesem Tag.").foregroundStyle(.secondary) }
            ForEach(ds) { s in
                NavigationLink { SessionDetailView(session: s) } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        VStack(alignment: .leading) {
                            Text(s.dayName).font(.headline)
                            Text("\(s.doneSets.count) Sätze · \(Int(s.volume)) kg · \(s.duration.minutesText)").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            ForEach(ps) { p in
                HStack {
                    VStack(alignment: .leading) {
                        Text(p.dayName).font(.headline)
                        Text("Geplant · \(p.date.formatted(date: .omitted, time: .shortened)) Uhr").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cal.isDateInToday(p.date), let day = plan?.sortedDays, day.indices.contains(p.dayIndex) {
                        Button("Starten") { router.session = Workout.start(day[p.dayIndex], ctx) }.buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct ScheduleEditor: View {
    @Environment(\.modelContext) private var ctx
    @Query private var slots: [TrainingSlot]
    @Query private var plans: [Plan]
    private var sorted: [TrainingSlot] { slots.sorted { (($0.weekday + 5) % 7, $0.hour, $0.minute) < (($1.weekday + 5) % 7, $1.hour, $1.minute) } }
    private var names: [String] { plans.first { $0.isActive }?.sortedDays.map(\.name) ?? [] }

    var body: some View {
        List {
            Section {
                ForEach(sorted) { SlotRow(slot: $0, names: names) }
                    .onDelete { offs in offs.forEach { ctx.delete(sorted[$0]) } }
                Button("Trainingstag hinzufügen", systemImage: "plus.circle.fill") { ctx.insert(TrainingSlot(weekday: 2, hour: 18)) }
            } footer: {
                Text("Das Training wechselt automatisch durch die Trainingstage deines aktiven Plans (A → B → A …). Einzelne Tage kannst du auch fest einem Training zuordnen oder deaktivieren.")
            }
        }
        .navigationTitle("Trainingstage")
        .onDisappear { Task { await Notifier.refresh(ctx) } }
    }
}

struct SlotRow: View {
    @Bindable var slot: TrainingSlot
    let names: [String]
    private var time: Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: .now) ?? .now },
                set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0); slot.hour = c.hour ?? 18; slot.minute = c.minute ?? 0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Aktiv", isOn: $slot.enabled).labelsHidden()
                Picker("Wochentag", selection: $slot.weekday) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                }
                .labelsHidden()
                Spacer()
                DatePicker("Uhrzeit", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
            }
            Picker("Training", selection: $slot.fixedDay) {
                Text("Automatischer Wechsel").tag(-1)
                ForEach(names.indices, id: \.self) { Text(names[$0]).tag($0) }
            }
            .font(.subheadline)
        }
        .opacity(slot.enabled ? 1 : 0.5)
    }
}
