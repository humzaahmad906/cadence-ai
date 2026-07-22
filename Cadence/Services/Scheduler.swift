import Foundation
import SwiftUI
import Combine

@MainActor
final class Scheduler: ObservableObject {
    private var timer: Timer?
    private weak var appState: AppState?
    private var lastMorningBrief: Date?
    private var lastDigestDraft: Date?
    private var lastDigestCopy: Date?
    private var lastIdleScan: Date?

    func start(appState: AppState) {
        self.appState = appState
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func handle(url: URL, appState: AppState) {
        // cadence://digest, cadence://brief
        switch url.host {
        case "digest": Task { await appState.generateDigestDraft() }
        case "copy":   Task { await appState.copyDigestNow() }
        case "brief":  Task { await self.morningBrief() }
        default: break
        }
    }

    private func tick() {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)

        // 09:00 morning brief
        if comps.hour == 9 && comps.minute == 0 && !sameDay(lastMorningBrief, now) {
            lastMorningBrief = now
            Task { await morningBrief() }
        }
        // hourly idle + sprint scan
        if lastIdleScan == nil || now.timeIntervalSince(lastIdleScan!) > 3600 {
            lastIdleScan = now
            Task { await idleAndDeadlineScan() }
        }
    }

    private func sameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func morningBrief() async {
        guard let s = appState else { return }
        await s.refresh()
        let top = s.tickets
            .filter { $0.status != .done }
            .sorted { $0.priority.rank < $1.priority.rank }
            .prefix(3)
            .map { "• [\($0.priority.rawValue)] \($0.title)" }
            .joined(separator: "\n")
        let daysLeft = s.currentSprint?.daysLeft ?? 0
        Notifier.post(
            title: "Morning — \(daysLeft)d left in sprint",
            body: top.isEmpty ? "No open tickets." : top
        )
    }

    private func idleAndDeadlineScan() async {
        guard let s = appState else { return }
        let cutoff = Date().addingTimeInterval(-2 * 24 * 3600)
        let iso = ISO8601DateFormatter()
        for t in s.tickets where t.status == .inProgress && (iso.date(from: t.updated) ?? .distantPast) < cutoff {
            Notifier.post(title: "Idle task > 2d", body: t.title)
        }
        if let sp = s.currentSprint, sp.daysLeft <= 3 {
            let openUrgent = s.tickets.filter { $0.priority.urgent && $0.status != .done }
            if !openUrgent.isEmpty {
                let list = openUrgent.prefix(5).map { "[\($0.priority.rawValue)] \($0.title)" }.joined(separator: ", ")
                Notifier.post(title: "Sprint ends in \(sp.daysLeft)d — urgent open", body: list)
            }
        }
    }
}
