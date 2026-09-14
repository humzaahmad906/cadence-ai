import SwiftUI
import UserNotifications

@main
struct CadenceApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduler = Scheduler()
    @StateObject private var router = NotificationRouter()

    var body: some Scene {
        WindowGroup("Cadence") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(scheduler)
                .preferredColorScheme(.light)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    // Auth first: the scheduler checks the office network the moment it starts,
                    // and a notification posted before the prompt is answered is dropped without
                    // a trace — which is exactly the login-time arrival we care about.
                    router.install()
                    await requestNotificationAuth()
                    await appState.bootstrap()
                    scheduler.start(appState: appState)
                }
                .onOpenURL { url in
                    scheduler.handle(url: url, appState: appState)
                }
                .onReceive(router.$pendingURL.compactMap { $0 }) { url in
                    scheduler.handle(url: url, appState: appState)
                    router.pendingURL = nil
                    NSApp.activate(ignoringOtherApps: true)
                }
        }

        // Only in the menu bar while a block is actually being timed — no idle icon parked up
        // there the rest of the day.
        MenuBarExtra(isInserted: Binding(
            get: { appState.day.runningBlockId != nil },
            set: { _ in })) {
            TimerMenuBarContent(appState: appState, ticker: appState.ticker)
        } label: {
            TimerMenuBarLabel(appState: appState, ticker: appState.ticker)
        }
        .menuBarExtraStyle(.menu)
    }

    private func requestNotificationAuth() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }
}

/// Turns a notification tap into a `cadence://` route. Without a delegate the tap only
/// foregrounds the app, which for the office-arrival alert would drop you wherever you left
/// off instead of on Day.
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var pendingURL: URL?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["url"] as? String, let url = URL(string: raw) else { return }
        await MainActor.run { self.pendingURL = url }
    }

    /// Show the banner even when Cadence is the frontmost app — a block starting matters
    /// whether or not you're looking at the window.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
