import SwiftUI
import SwiftData
import Charts
import UserNotifications

struct ProfileView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @AppStorage("userName") private var userName = ""
    @AppStorage("goalKg") private var goal = 0.0
    @AppStorage("notifOn") private var on = true
    @AppStorage("leadMin") private var lead = 30
    @AppStorage("nBefore") private var nBefore = true
    @AppStorage("nStart") private var nStart = true
    @AppStorage("nMissed") private var nMissed = true
    @AppStorage("missedMin") private var missed = 120
    @AppStorage("inc") private var inc = 2.5
    @AppStorage("anchor") private var anchor = 0.0
    @State private var denied = false
    @State private var showWeight = false

    private var key: String { "\(on)\(lead)\(nBefore)\(nStart)\(nMissed)\(missed)" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profil") {
                    TextField("Name", text: $userName)
                    HStack {
                        Text("Zielgewicht"); Spacer()
                        TextField("kg", value: $goal, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("kg")
                    }
                }
                Section("Körpergewicht") {
                    if let l = weights.last {
                        LabeledContent("Aktuell", value: "\(l.kg.fmt) kg")
                        if goal > 0 { LabeledContent("Bis zum Ziel", value: "\(abs(l.kg - goal).fmt) kg") }
                    }
                    Button("Gewicht eintragen", systemImage: "plus.circle.fill") { showWeight = true }
                    NavigationLink("Verlauf") { BodyWeightView() }
                }
                Section {
                    Toggle("Erinnerungen", isOn: $on)
                    if on {
                        Toggle("Vorab erinnern", isOn: $nBefore)
                        if nBefore { Stepper("\(lead) Min. vorher", value: $lead, in: 5...180, step: 5) }
                        Toggle("Zur Trainingszeit", isOn: $nStart)
                        Toggle("Wenn nicht abgeschlossen", isOn: $nMissed)
                        if nMissed { Stepper("\(missed) Min. nach Beginn", value: $missed, in: 30...480, step: 30) }
                    }
                    if denied { Link("Mitteilungen in den iOS-Einstellungen erlauben", destination: URL(string: UIApplication.openSettingsURLString)!) }
                } header: { Text("Benachrichtigungen") } footer: { Text("Die Uhrzeiten richten sich nach deinen Trainingszeiten im Kalender.") }
                Section("Training") {
                    Stepper("Steigerung: \(inc.fmt) kg", value: $inc, in: 0.5...10, step: 0.5)
                    Button("A/B-Wechsel ab heute neu starten") {
                        anchor = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
                        Task { await Notifier.refresh(ctx) }
                    }
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showWeight) { WeightSheet() }
            .task { await checkAuth() }
            .onChange(of: key) { Task { await Notifier.refresh(ctx); await checkAuth() } }
        }
    }
    private func checkAuth() async { denied = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied }
}

struct WeightSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyWeightEntry.date) private var all: [BodyWeightEntry]
    @State private var kg = 0.0
    @State private var date = Date.now
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: ...Date.now, displayedComponents: .date)
                HStack {
                    Text("Gewicht"); Spacer()
                    TextField("kg", value: $kg, format: .number.precision(.fractionLength(0...1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("kg")
                }
            }
            .navigationTitle("Körpergewicht").navigationBarTitleDisplayMode(.inline)
            .onAppear { if let l = all.last { kg = l.kg } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Sichern") { save() }.bold().disabled(kg <= 0) }
            }
        }
        .presentationDetents([.medium])
    }
    private func save() {
        all.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.forEach { ctx.delete($0) }
        ctx.insert(BodyWeightEntry(date: date, kg: kg))
        dismiss()
    }
}

struct BodyWeightView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \BodyWeightEntry.date) private var all: [BodyWeightEntry]
    @State private var showWeight = false
    var body: some View {
        List {
            if all.count > 1 {
                Section {
                    Chart(all) { e in
                        LineMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).interpolationMethod(.catmullRom).foregroundStyle(.green)
                        PointMark(x: .value("Datum", e.date), y: .value("kg", e.kg)).foregroundStyle(.green)
                    }
                    .chartYScale(domain: .automatic(includesZero: false)).frame(height: 200)
                }
            }
            Section("Einträge") {
                ForEach(all.reversed()) { e in
                    HStack { Text(e.date.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text("\(e.kg.fmt) kg").monospacedDigit() }
                }
                .onDelete { offs in let r = Array(all.reversed()); offs.forEach { ctx.delete(r[$0]) } }
            }
        }
        .navigationTitle("Körpergewicht")
        .toolbar { Button("Eintragen", systemImage: "plus") { showWeight = true } }
        .sheet(isPresented: $showWeight) { WeightSheet() }
    }
}
