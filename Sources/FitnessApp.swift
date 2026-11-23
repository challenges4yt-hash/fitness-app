import SwiftUI
import SwiftData
import UserNotifications

@main
struct FitnessApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    let container: ModelContainer

    init() {
        UserDefaults.standard.register(defaults: ["notifOn": true, "leadMin": 30, "nBefore": true, "nStart": true, "nMissed": true, "missedMin": 120, "inc": 2.5])
        do {
            container = try ModelContainer(for: Exercise.self, Plan.self, PlanDay.self, PlanItem.self, TrainingSlot.self,
                                           WorkoutSession.self, SetLog.self, BodyWeightEntry.self, PersonalRecord.self)
        } catch { fatalError("Datenbank konnte nicht geladen werden: \(error)") }
    }
    var body: some Scene { WindowGroup { RootView() }.modelContainer(container) }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.identifier == "rest" ? [.sound] : [.banner, .sound])
    }
}

@Observable final class Router {
    var session: WorkoutSession?
    var tab = 0
}

struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @State private var router = Router()

    var body: some View {
        @Bindable var r = router
        TabView(selection: $r.tab) {
            DashboardView().tabItem { Label("Übersicht", systemImage: "house.fill") }.tag(0)
            TrainingView().tabItem { Label("Training", systemImage: "dumbbell.fill") }.tag(1)
            CalendarView().tabItem { Label("Kalender", systemImage: "calendar") }.tag(2)
            ProgressTab().tabItem { Label("Fortschritt", systemImage: "chart.line.uptrend.xyaxis") }.tag(3)
            ProfileView().tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }.tag(4)
        }
        .tint(.green)
        .environment(router)
        .fullScreenCover(item: $r.session) { WorkoutView(session: $0) }
        .task { Seed.run(ctx); await Notifier.refresh(ctx) }
        .onChange(of: phase) { _, p in if p == .active { Task { await Notifier.refresh(ctx) } } }
    }
}

// MARK: - Wiederverwendbare Komponenten

struct Card<C: View>: View {
    let title: String?
    let content: C
    init(title: String? = nil, @ViewBuilder content: () -> C) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct Stat: View {
    let icon: String, value: String, label: String
    var tint: Color = .green
    var body: some View {
        Card {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.multilineTextAlignment(.center).frame(width: 78).padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
extension View { func field() -> some View { modifier(FieldStyle()) } }
