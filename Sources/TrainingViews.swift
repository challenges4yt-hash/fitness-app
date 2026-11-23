import SwiftUI
import SwiftData
import PhotosUI

struct TrainingView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Plan.name) private var plans: [Plan]
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Trainingspläne") {
                    ForEach(plans) { p in
                        NavigationLink { PlanDetailView(plan: p) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(p.name).font(.headline)
                                    if p.isActive { Text("Aktiv").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 2).background(Color.green.opacity(0.2), in: Capsule()).foregroundStyle(.green) }
                                }
                                Text("\(p.days.count) Trainingstage · \(p.days.reduce(0) { $0 + $1.items.count }) Übungen").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Löschen", role: .destructive) { delete(p) }
                            Button("Duplizieren") { duplicate(p) }.tint(.blue)
                        }
                        .contextMenu {
                            Button("Als aktiven Plan setzen", systemImage: "checkmark.circle") { activate(p) }
                            Button("Duplizieren", systemImage: "plus.square.on.square") { duplicate(p) }
                        }
                    }
                }
                Section { NavigationLink { ExerciseLibrary() } label: { Label("Übungen verwalten", systemImage: "list.bullet") } }
            }
            .navigationTitle("Training")
            .toolbar { Button("Neuer Plan", systemImage: "plus") { newName = ""; adding = true } }
            .alert("Neuer Plan", isPresented: $adding) {
                TextField("Name", text: $newName)
                Button("Erstellen") { create() }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    private func create() {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let p = Plan(name: n, isActive: plans.isEmpty); ctx.insert(p)
        let d = PlanDay(name: "Training A", order: 0); ctx.insert(d); d.plan = p
    }
    private func activate(_ p: Plan) {
        plans.forEach { $0.isActive = ($0 === p) }
        Task { await Notifier.refresh(ctx) }
    }
    private func delete(_ p: Plan) {
        let was = p.isActive
        ctx.delete(p)
        if was, let other = plans.first(where: { $0 !== p }) { activate(other) }
    }
    private func duplicate(_ p: Plan) {
        let n = Plan(name: p.name + " Kopie"); ctx.insert(n)
        for d in p.sortedDays {
            let nd = PlanDay(name: d.name, order: d.order); ctx.insert(nd); nd.plan = n
            for it in d.sortedItems {
                let ni = PlanItem(order: it.order, sets: it.sets, repMin: it.repMin, repMax: it.repMax, startWeight: it.startWeight)
                ctx.insert(ni); ni.day = nd; ni.exercise = it.exercise
            }
        }
    }
}

struct PlanDetailView: View {
    @Bindable var plan: Plan
    @Environment(\.modelContext) private var ctx
    @Environment(Router.self) private var router
    @State private var pickDay: PlanDay?
    @State private var editItem: PlanItem?
    @State private var showName = false
    @State private var nameTitle = ""
    @State private var nameText = ""
    @State private var nameAction: ((String) -> Void)?

    var body: some View {
        List {
            ForEach(plan.sortedDays) { day in
                Section {
                    ForEach(day.sortedItems) { it in
                        Button { editItem = it } label: { row(it) }.buttonStyle(.plain)
                            .contextMenu {
                                Menu("Verschieben nach …", systemImage: "arrow.right.circle") {
                                    ForEach(plan.sortedDays.filter { $0 !== day }) { t in Button(t.name) { it.order = t.items.count; it.day = t } }
                                }
                            }
                    }
                    .onMove { from, to in move(day, from, to) }
                    .onDelete { offs in let arr = day.sortedItems; offs.forEach { ctx.delete(arr[$0]) } }
                    Button("Übung hinzufügen", systemImage: "plus.circle.fill") { pickDay = day }
                } header: {
                    HStack {
                        Text(day.name).font(.headline).textCase(nil)
                        Spacer()
                        Menu {
                            Button("Training starten", systemImage: "play.fill") { router.session = Workout.start(day, ctx) }
                            Button("Umbenennen", systemImage: "pencil") { ask("Training umbenennen", day.name) { day.name = $0 } }
                            Button("Löschen", systemImage: "trash", role: .destructive) { ctx.delete(day) }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .navigationTitle(plan.name)
        .toolbar {
            EditButton()
            Menu {
                Button("Trainingstag hinzufügen", systemImage: "plus") {
                    ask("Neuer Trainingstag", "Training \(Character(UnicodeScalar(65 + min(plan.days.count, 25))!))") { n in
                        let d = PlanDay(name: n, order: plan.days.count); ctx.insert(d); d.plan = plan
                    }
                }
                Button("Plan umbenennen", systemImage: "pencil") { ask("Plan umbenennen", plan.name) { plan.name = $0 } }
                if !plan.isActive { Button("Als aktiven Plan setzen", systemImage: "checkmark.circle") { setActive() } }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(item: $pickDay) { day in ExercisePicker { add($0, to: day) } }
        .sheet(item: $editItem) { PlanItemEditor(item: $0) }
        .alert(nameTitle, isPresented: $showName) {
            TextField("Name", text: $nameText)
            Button("OK") { let t = nameText.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { nameAction?(t) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func ask(_ title: String, _ initial: String, _ action: @escaping (String) -> Void) {
        nameTitle = title; nameText = initial; nameAction = action; showName = true
    }
    private func setActive() {
        let all = (try? ctx.fetch(FetchDescriptor<Plan>())) ?? []
        all.forEach { $0.isActive = ($0 === plan) }
        Task { await Notifier.refresh(ctx) }
    }
    private func row(_ it: PlanItem) -> some View {
        let unit = it.exercise?.isTimed == true ? "Sek." : "Wdh."
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(it.exercise?.name ?? "–")
                Text("\(it.sets) × \(it.repMin)–\(it.repMax) \(unit)" + (it.startWeight > 0 ? " · \(it.startWeight.fmt) kg" : ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }
    }
    private func move(_ day: PlanDay, _ from: IndexSet, _ to: Int) {
        var arr = day.sortedItems
        arr.move(fromOffsets: from, toOffset: to)
        for (i, it) in arr.enumerated() { it.order = i }
    }
    private func add(_ e: Exercise, to day: PlanDay) {
        let it = PlanItem(order: day.items.count, sets: e.isTimed ? 2 : 3, repMin: e.isTimed ? 20 : 10, repMax: e.isTimed ? 40 : 12)
        ctx.insert(it); it.day = day; it.exercise = e
    }
}

struct PlanItemEditor: View {
    @Bindable var item: PlanItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let timed = item.exercise?.isTimed == true
        NavigationStack {
            Form {
                if let e = item.exercise { Section { Text(e.name).font(.headline); if !e.muscle.isEmpty { Text(e.muscle).foregroundStyle(.secondary) } } }
                Section {
                    Stepper("Sätze: \(item.sets)", value: $item.sets, in: 1...10)
                    Stepper("\(timed ? "Sekunden" : "Wdh.") von: \(item.repMin)", value: $item.repMin, in: 1...300, step: timed ? 5 : 1)
                    Stepper("\(timed ? "Sekunden" : "Wdh.") bis: \(item.repMax)", value: $item.repMax, in: 1...300, step: timed ? 5 : 1)
                    if !timed {
                        HStack {
                            Text("Startgewicht"); Spacer()
                            TextField("kg", value: $item.startWeight, format: .number.precision(.fractionLength(0...2))).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 80)
                            Text("kg")
                        }
                    }
                }
            }
            .navigationTitle("Übung im Plan").navigationBarTitleDisplayMode(.inline)
            .onChange(of: item.repMin) { _, v in if item.repMax < v { item.repMax = v } }
            .onChange(of: item.repMax) { _, v in if item.repMin > v { item.repMin = v } }
            .toolbar { Button("Fertig") { dismiss() }.bold() }
        }
        .presentationDetents([.medium])
    }
}

struct ExerciseLibrary: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Exercise.name) private var all: [Exercise]
    @State private var search = ""
    @State private var editing: Exercise?
    @State private var creating = false
    private var list: [Exercise] {
        search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.muscle.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            ForEach(list) { e in
                Button { editing = e } label: {
                    HStack(spacing: 12) {
                        if let d = e.imageData, let ui = UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10)) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name)
                            Text(e.muscle.isEmpty ? "Keine Muskelgruppe" : e.muscle).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offs in offs.forEach { ctx.delete(list[$0]) } }
        }
        .searchable(text: $search)
        .navigationTitle("Übungen")
        .toolbar { Button("Neue Übung", systemImage: "plus") { creating = true } }
        .sheet(item: $editing) { ExerciseEditor(exercise: $0) }
        .sheet(isPresented: $creating) { ExerciseEditor(exercise: nil) }
    }
}

struct ExercisePicker: View {
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var all: [Exercise]
    @State private var search = ""
    @State private var creating = false
    var body: some View {
        NavigationStack {
            List(search.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(search) }) { e in
                Button { onPick(e); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 2) { Text(e.name); Text(e.muscle).font(.footnote).foregroundStyle(.secondary) }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search)
            .navigationTitle("Übung wählen").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Neue Übung", systemImage: "plus") { creating = true } }
            }
            .sheet(isPresented: $creating) { ExerciseEditor(exercise: nil) }
        }
    }
}

struct ExerciseEditor: View {
    let exercise: Exercise?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var muscle: String
    @State private var bodyweight: Bool
    @State private var timed: Bool
    @State private var rest: Int
    @State private var notes: String
    @State private var imageData: Data?
    @State private var photo: PhotosPickerItem?
    @State private var confirmDelete = false

    init(exercise: Exercise?) {
        self.exercise = exercise
        _name = State(initialValue: exercise?.name ?? "")
        _muscle = State(initialValue: exercise?.muscle ?? "")
        _bodyweight = State(initialValue: exercise?.isBodyweight ?? false)
        _timed = State(initialValue: exercise?.isTimed ?? false)
        _rest = State(initialValue: exercise?.rest ?? 90)
        _notes = State(initialValue: exercise?.notes ?? "")
        _imageData = State(initialValue: exercise?.imageData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Muskelgruppe(n)", text: $muscle)
                    Menu("Muskelgruppe auswählen") {
                        ForEach(["Brust", "Rücken", "Schultern", "Bizeps", "Trizeps", "Beine", "Gesäß", "Bauch · Rumpf", "Ganzkörper"], id: \.self) { m in Button(m) { muscle = m } }
                    }
                }
                Section {
                    Toggle("Körpergewichtsübung", isOn: $bodyweight)
                    Toggle("Zeitbasiert (Sekunden)", isOn: $timed)
                    Stepper("Pause: \(rest) Sek.", value: $rest, in: 15...300, step: 15)
                }
                Section("Beschreibung & Bild") {
                    TextField("Beschreibung (optional)", text: $notes, axis: .vertical).lineLimit(2...6)
                    if let d = imageData, let ui = UIImage(data: d) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 14))
                        Button("Bild entfernen", role: .destructive) { imageData = nil }
                    }
                    PhotosPicker(selection: $photo, matching: .images) { Label(imageData == nil ? "Bild auswählen" : "Bild ändern", systemImage: "photo") }
                }
                if let exercise {
                    Section {
                        Button("Übung löschen", role: .destructive) { confirmDelete = true }
                    } footer: { Text("Die Übung wird auch aus allen Plänen entfernt. Deine Trainingshistorie bleibt erhalten.") }
                    .confirmationDialog("Übung löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Löschen", role: .destructive) { ctx.delete(exercise); dismiss() }
                    }
                }
            }
            .navigationTitle(exercise == nil ? "Neue Übung" : "Übung bearbeiten").navigationBarTitleDisplayMode(.inline)
            .onChange(of: photo) { _, new in
                Task {
                    if let d = try? await new?.loadTransferable(type: Data.self), let ui = UIImage(data: d) { imageData = ui.jpegData(compressionQuality: 0.6) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Sichern") { save() }.bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = exercise ?? Exercise(name: n)
        if exercise == nil { ctx.insert(e) }
        let old = e.name
        if old != n && exercise != nil {   // Umbenennen: Historie und Bestleistungen mitziehen
            for s in (try? ctx.fetch(FetchDescriptor<SetLog>(predicate: #Predicate<SetLog> { $0.exerciseName == old }))) ?? [] { s.exerciseName = n }
            for p in (try? ctx.fetch(FetchDescriptor<PersonalRecord>(predicate: #Predicate<PersonalRecord> { $0.name == old }))) ?? [] { p.name = n }
        }
        e.name = n; e.muscle = muscle; e.isBodyweight = bodyweight; e.isTimed = timed; e.rest = rest; e.notes = notes; e.imageData = imageData
        dismiss()
    }
}
