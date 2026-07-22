import SwiftUI
import UserNotifications

@main
struct CadenceApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var scheduler = Scheduler()

    var body: some Scene {
        WindowGroup("Cadence") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(scheduler)
                .preferredColorScheme(.light)
                .frame(minWidth: 1200, minHeight: 720)
                .task {
                    await appState.bootstrap()
                    scheduler.start(appState: appState)
                    await requestNotificationAuth()
                }
                .onOpenURL { url in
                    scheduler.handle(url: url, appState: appState)
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Paste Sprint…") { appState.showPasteSprint = true }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Copy Digest to Clipboard") { Task { await appState.copyDigestNow() } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }

    private func requestNotificationAuth() async {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("notif auth failed: \(error)")
        }
    }
}
