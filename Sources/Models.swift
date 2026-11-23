import Foundation
import SwiftData
import UserNotifications

extension Double { var fmt: String { formatted(.number.precision(.fractionLength(0...2))) } }
extension TimeInterval {
    var minutesText: String { let m = Int(self) / 60; return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(max(m, 1)) min" }
}

// MARK: - Datenmodell (SwiftData, lokal & dauerhaft)

@Model final class Exercise {
    var name: String; var muscle: String; var rest: Int
    var isBodyweight: Bool; var isTimed: Bool; var notes: String
    @Attribute(.externalStorage) var imageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \PlanItem.exercise) var items: [PlanItem] = []
    init(name: String, muscle: String = "", rest: Int = 90, isBodyweight: Bool = false, isTimed: Bool = false, notes: String = "") {
        self.name = name; self.muscle = muscle; self.rest = rest
        self.isBodyweight = isBodyweight; self.isTimed = isTimed; self.notes = notes
    }
}

@Model final class Plan {
    var name: String; var isActive: Bool
    @Relationship(deleteRule: .cascade, inverse: \PlanDay.plan) var days: [PlanDay] = []
    init(name: String, isActive: Bool = false) { self.name = name; self.isActive = isActive }
    var sortedDays: [PlanDay] { days.sorted { $0.order < $1.order } }
}

@Model final class PlanDay {
    var name: String; var order: Int; var plan: Plan?
    @Relationship(deleteRule: .cascade, inverse: \PlanItem.day) var items: [PlanItem] = []
    init(name: String, order: Int) { self.name = name; self.order = order }
    var sortedItems: [PlanItem] { items.filter { $0.exercise != nil }.sorted { $0.order < $1.order } }
}

@Model final class PlanItem {
    var order: Int; var sets: Int; var repMin: Int; var repMax: Int; var startWeight: Double
    var exercise: Exercise?; var day: PlanDay?
    init(order: Int, sets: Int, repMin: Int, repMax: Int, startWeight: Double = 0) {
        self.order = order; self.sets = sets; self.repMin = repMin; self.repMax = repMax; self.startWeight = startWeight
    }
}

/// Trainingstag: weekday 1 = Sonntag … 7 = Samstag. fixedDay = -1 → automatischer A/B-Wechsel.
@Model final class TrainingSlot {
    var weekday: Int; var hour: Int; var minute: Int; var enabled: Bool; var fixedDay: Int
    init(weekday: Int, hour: Int, minute: Int = 0, enabled: Bool = true, fixedDay: Int = -1) {
        self.weekday = weekday; self.hour = hour; self.minute = minute; self.enabled = enabled; self.fixedDay = fixedDay
    }
}

@Model final class WorkoutSession {
    var start: Date; var end: Date?; var dayName: String; var planName: String; var finished: Bool
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session) var sets: [SetLog] = []
    init(dayName: String, planName: String) { start = .now; self.dayName = dayName; self.planName = planName; finished = false }
    var doneSets: [SetLog] { sets.filter(\.done) }
    var volume: Double { doneSets.filter { !$0.isTimed }.reduce(0) { $0 + $1.weight * Double($1.reps) } }
    var duration: TimeInterval { (end ?? .now).timeIntervalSince(start) }
    var exerciseCount: Int { Set(doneSets.map(\.exerciseName)).count }
}

/// Ein einzelner Satz: Datum, Übung, Gewicht, Wiederholungen – dauerhaft gespeichert.
@Model final class SetLog {
    var exerciseName: String; var muscle: String; var exOrder: Int; var setIndex: Int
    var weight: Double; var reps: Int; var done = false
    var isBodyweight: Bool; var isTimed: Bool
    var repMin: Int; var repMax: Int; var rest: Int
    var date: Date
    var prevWeight = 0.0; var prevReps = 0; var suggested = 0.0; var isPR = false
    var session: WorkoutSession?
    init(name: String, muscle: String, exOrder: Int, setIndex: Int, weight: Double, reps: Int, bw: Bool, timed: Bool,
         repMin: Int, repMax: Int, rest: Int, date: Date) {
        exerciseName = name; self.muscle = muscle; self.exOrder = exOrder; self.setIndex = setIndex
        self.weight = weight; self.reps = reps; isBodyweight = bw; isTimed = timed
        self.repMin = repMin; self.repMax = repMax; self.rest = rest; self.date = date
    }
    /// Vergleichswert für Bestleistungen (geschätztes 1RM nach Epley; bei Körpergewicht: Zusatzgewicht, dann Wdh.)
    var score: Double { isTimed ? Double(reps) : isBodyweight ? weight * 1000 + Double(reps) : weight * (1 + Double(reps) / 30) }
    var summary: String { isTimed ? "\(reps) Sek." : weight > 0 ? "\(weight.fmt) kg × \(reps)" : "\(reps) Wdh." }
}

@Model final class BodyWeightEntry {
    var date: Date; var kg: Double
    init(date: Date, kg: Double) { self.date = date; self.kg = kg }
}

@Model final class PersonalRecord {
    var name: String; var weight: Double; var reps: Int; var date: Date
    init(name: String, weight: Double, reps: Int, date: Date) { self.name = name; self.weight = weight; self.reps = reps; self.date = date }
}

// MARK: - Startdaten (integrierter Trainingsplan)

@MainActor enum Seed {
    static func run(_ c: ModelContext) {
        let d = UserDefaults.standard
        if d.double(forKey: "anchor") == 0 { d.set(Calendar.current.startOfDay(for: .now).timeIntervalSince1970, forKey: "anchor") }
        guard !d.bool(forKey: "seeded") else { return }
        d.set(true, forKey: "seeded")
        func ex(_ n: String, _ m: String, rest: Int = 90, bw: Bool = false, timed: Bool = false) -> Exercise {
            let e = Exercise(name: n, muscle: m, rest: rest, isBodyweight: bw, isTimed: timed); c.insert(e); return e
        }
        let bench = ex("Bankdrücken", "Brust · vordere Schulter · Trizeps", rest: 120)
        let lat = ex("Latzug zur Brust", "Rücken · Bizeps")
        let leg = ex("Beinpresse", "Oberschenkel · Gesäß", rest: 120)
        let fly = ex("Butterfly", "Brust", rest: 60)
        let curl = ex("Beinbeuger sitzend", "Oberschenkelrückseite", rest: 60)
        let lateral = ex("Seitheben", "Seitliche Schultern", rest: 60)
        let plank = ex("Plank", "Bauch · Rumpf", rest: 45, bw: true, timed: true)
        let row = ex("Sitzendes Rudern", "Rücken · hintere Schulter · Bizeps")
        let press = ex("Schulterdrücken (Maschine)", "Schultern · Trizeps")
        let bic = ex("Bizepscurls", "Bizeps", rest: 60)
        let tri = ex("Trizepsdrücken (Kabel)", "Trizeps", rest: 60)
        let plan = Plan(name: "Ganzkörper Anfänger", isActive: true); c.insert(plan)
        func day(_ n: String, _ o: Int, _ rows: [(Exercise, Int, Int, Int)]) {
            let pd = PlanDay(name: n, order: o); c.insert(pd); pd.plan = plan
            for (i, r) in rows.enumerated() {
                let it = PlanItem(order: i, sets: r.1, repMin: r.2, repMax: r.3); c.insert(it); it.day = pd; it.exercise = r.0
            }
        }
        day("Training A", 0, [(bench, 3, 8, 12), (lat, 3, 10, 12), (leg, 3, 10, 12), (fly, 2, 12, 15), (curl, 2, 12, 15), (lateral, 2, 12, 15), (plank, 2, 20, 40)])
        day("Training B", 1, [(row, 3, 10, 12), (bench, 3, 8, 12), (leg, 3, 10, 12), (lat, 3, 10, 12), (press, 2, 10, 12), (bic, 2, 10, 12), (tri, 2, 10, 12)])
        for (wd, h) in [(2, 18), (4, 18), (6, 16)] { c.insert(TrainingSlot(weekday: wd, hour: h)) }
        try? c.save()
    }
}

// MARK: - Wochenplan mit automatischem A/B-Wechsel

struct Planned: Identifiable {
    let date: Date, dayIndex: Int, dayName: String
    var id: String { "\(date.timeIntervalSince1970)-\(dayName)" }
}

enum Schedule {
    static func anchorDate(_ t: Double) -> Date { t > 0 ? Date(timeIntervalSince1970: t) : .now }

    /// Alle geplanten Trainings im Zeitraum. Der Wechsel läuft ab dem Startdatum (anchor) fortlaufend durch die Trainingstage des Plans.
    static func planned(slots: [TrainingSlot], days: [String], anchor: Date, from: Date, to: Date) -> [Planned] {
        guard !days.isEmpty else { return [] }
        let cal = Calendar.current
        let active = slots.filter(\.enabled)
        var out: [Planned] = []; var rot = 0
        var day = cal.startOfDay(for: min(anchor, from))
        while day <= to {
            let wd = cal.component(.weekday, from: day)
            for s in active.filter({ $0.weekday == wd }).sorted(by: { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) {
                guard let date = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: day) else { continue }
                var idx = s.fixedDay
                let counts = day >= cal.startOfDay(for: anchor)
                if idx < 0 || idx >= days.count { idx = rot % days.count; if counts { rot += 1 } }
                if date >= from && counts { out.append(Planned(date: date, dayIndex: idx, dayName: days[idx])) }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}

// MARK: - Trainingslogik

@MainActor enum Workout {
    static func openSession(_ c: ModelContext) -> WorkoutSession? {
        var d = FetchDescriptor<WorkoutSession>(predicate: #Predicate<WorkoutSession> { !$0.finished }, sortBy: [SortDescriptor(\.start, order: .reverse)])
        d.fetchLimit = 1
        return try? c.fetch(d).first
    }

    static func lastSets(_ name: String, before: Date, _ c: ModelContext) -> [SetLog] {
        var d = FetchDescriptor<SetLog>(predicate: #Predicate<SetLog> { $0.exerciseName == name && $0.done && $0.date < before },
                                        sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.setIndex)])
        d.fetchLimit = 20
        let all = (try? c.fetch(d)) ?? []
        guard let first = all.first else { return [] }
        return all.filter { $0.date == first.date }
    }

    /// Startet ein Training (oder setzt ein unterbrochenes fort). Gewichte werden mit den letzten Werten vorausgefüllt.
    static func start(_ day: PlanDay, _ c: ModelContext) -> WorkoutSession {
        if let open = openSession(c) { return open }
        let s = WorkoutSession(dayName: day.name, planName: day.plan?.name ?? ""); c.insert(s)
        let inc = UserDefaults.standard.double(forKey: "inc")
        for (n, it) in day.sortedItems.enumerated() {
            guard let e = it.exercise else { continue }
            let last = lastSets(e.name, before: s.start, c)
            let reached = !e.isTimed && last.count >= it.sets && last.allSatisfy { $0.reps >= it.repMax }
            let suggestion = reached ? (last.map(\.weight).max() ?? 0) + inc : 0
            for i in 0..<it.sets {
                let p = i < last.count ? last[i] : last.last
                let l = SetLog(name: e.name, muscle: e.muscle, exOrder: n, setIndex: i, weight: p?.weight ?? it.startWeight,
                               reps: p?.reps ?? it.repMax, bw: e.isBodyweight, timed: e.isTimed,
                               repMin: it.repMin, repMax: it.repMax, rest: e.rest, date: s.start)
                if i < last.count { l.prevWeight = last[i].weight; l.prevReps = last[i].reps }
                l.suggested = suggestion
                c.insert(l); l.session = s
            }
        }
        try? c.save()
        return s
    }

    static func finish(_ s: WorkoutSession, _ c: ModelContext) {
        for l in s.sets where !l.done { c.delete(l) }
        s.end = .now; s.finished = true
        rebuildPRs(c)
        try? c.save()
    }

    static func discard(_ s: WorkoutSession, _ c: ModelContext) { c.delete(s); try? c.save() }

    /// Erkennt Bestleistungen über die gesamte Historie neu und speichert sie.
    static func rebuildPRs(_ c: ModelContext) {
        let sets = (try? c.fetch(FetchDescriptor<SetLog>(predicate: #Predicate<SetLog> { $0.done },
                                                         sortBy: [SortDescriptor(\.date), SortDescriptor(\.setIndex)]))) ?? []
        for old in (try? c.fetch(FetchDescriptor<PersonalRecord>())) ?? [] { c.delete(old) }
        var best: [String: SetLog] = [:]
        let groups = Dictionary(grouping: sets) { "\($0.exerciseName)|\($0.date.timeIntervalSince1970)" }.values.sorted { $0[0].date < $1[0].date }
        for g in groups {
            g.forEach { $0.isPR = false }
            guard let top = g.max(by: { $0.score < $1.score }), top.score > 0 else { continue }
            if let prev = best[top.exerciseName] {
                if top.score > prev.score { top.isPR = true; best[top.exerciseName] = top }
            } else { best[top.exerciseName] = top }
        }
        for (name, s) in best { c.insert(PersonalRecord(name: name, weight: s.weight, reps: s.reps, date: s.date)) }
    }
}

// MARK: - Lokale Benachrichtigungen

@MainActor enum Notifier {
    static func refresh(_ c: ModelContext) async {
        let d = UserDefaults.standard, center = UNUserNotificationCenter.current(), cal = Calendar.current
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("wk-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard d.bool(forKey: "notifOn") else { return }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional else { return }

        let slots = (try? c.fetch(FetchDescriptor<TrainingSlot>())) ?? []
        let plans = (try? c.fetch(FetchDescriptor<Plan>(predicate: #Predicate<Plan> { $0.isActive }))) ?? []
        let names = plans.first?.sortedDays.map(\.name) ?? []
        let fin = (try? c.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate<WorkoutSession> { $0.finished }))) ?? []
        let trained = Set(fin.map { cal.startOfDay(for: $0.start) })
        let list = Schedule.planned(slots: slots, days: names, anchor: Schedule.anchorDate(d.double(forKey: "anchor")),
                                    from: .now, to: cal.date(byAdding: .day, value: 14, to: .now)!)
        let lead = Double(d.integer(forKey: "leadMin")) * 60, miss = Double(d.integer(forKey: "missedMin")) * 60

        var reqs: [UNNotificationRequest] = []
        func queue(_ id: String, _ fire: Date, _ body: String) {
            guard fire > .now else { return }
            let m = UNMutableNotificationContent(); m.title = "Fitness"; m.body = body; m.sound = .default
            let t = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            reqs.append(UNNotificationRequest(identifier: id, content: m, trigger: t))
        }
        for p in list.prefix(18) where !trained.contains(cal.startOfDay(for: p.date)) {
            let k = "wk-\(Int(p.date.timeIntervalSince1970))"
            if d.bool(forKey: "nBefore") && lead > 0 { queue(k + "-a", p.date.addingTimeInterval(-lead), "Heute steht \(p.dayName) an. Zeit, an deinem Ziel zu arbeiten! 💪") }
            if d.bool(forKey: "nStart") { queue(k + "-b", p.date, "Dein Training beginnt jetzt!") }
            if d.bool(forKey: "nMissed") { queue(k + "-c", p.date.addingTimeInterval(miss), "\(p.dayName) ist noch nicht abgeschlossen. Noch Zeit dafür?") }
        }
        for r in reqs { try? await center.add(r) }
    }

    static func rest(in seconds: TimeInterval) async {
        let m = UNMutableNotificationContent(); m.title = "Pause vorbei"; m.body = "Weiter geht's mit dem nächsten Satz!"; m.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "rest", content: m, trigger: t))
    }
}
