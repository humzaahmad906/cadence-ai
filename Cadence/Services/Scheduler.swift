import Foundation
import SwiftUI
import Combine

/// The app's only background clock. Ticks every 60s and does three things: roll the day plan
/// over at midnight, announce a block as it starts, and notice when we land on the office
/// network. Everything it does also lands in the activity log.
@MainActor
final class Scheduler: ObservableObject {
    private var timer: Timer?
    private weak var appState: AppState?

    let network = NetworkWatch()

    func start(appState: AppState) {
        self.appState = appState

        network.onArrive = { [weak self] office in
            self?.announceOfficeArrival(office)
        }
        network.start()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func handle(url: URL, appState: AppState) {
        // cadence://day, cadence://log
        switch url.host {
        case "day": appState.setArtifact(.day)
        case "log": appState.setArtifact(.activity)
        default: break
        }
    }

    private func tick() {
        guard let s = appState else { return }
        let now = Date()

        // Roll the day over at midnight — DayPlan.seed carries the block shape and anything
        // parked in Later, and drops yesterday's contents.
        if s.day.date != DayPlan.key(for: now) {
            s.loadDay()
            s.activityLog.append(ActivityEvent(kind: .dayRollover,
                                               title: "New day",
                                               detail: "\(s.day.blocks.count) blocks carried over",
                                               at: now))
        }

        announceBlockStart(now: now, state: s)
        network.refresh()
    }

    /// Fires once per block, inside the first few minutes of it. A window rather than an
    /// exact minute match means a brief sleep or a missed tick doesn't swallow the alert,
    /// while the 5-minute cap stops a stale burst when the app is opened mid-afternoon.
    private func announceBlockStart(now: Date, state s: AppState) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)

        var plan = s.day
        var cursor = plan.startMinutes
        var changed = false

        for block in plan.blocks {
            let into = mins - cursor
            if into >= 0, into < 5, !block.done, !plan.notified.contains(block.id) {
                plan.notified.append(block.id)
                changed = true

                let body = block.tasks.isEmpty
                    ? "\(durationLabel(block.minutes)) — nothing listed yet. Add it now."
                    : block.tasks.prefix(3).map { "• \($0.text)" }.joined(separator: "\n")

                Notifier.post(title: "Start: \(block.name)",
                              body: body,
                              id: "day-\(plan.date)-\(block.id)",
                              url: "cadence://day")

                s.activityLog.append(ActivityEvent(kind: .dayBlock,
                                                   title: "Started: \(block.name)",
                                                   detail: block.tasks.isEmpty
                                                       ? "\(durationLabel(block.minutes)), nothing listed"
                                                       : "\(durationLabel(block.minutes)) · \(block.tasks.count) task\(block.tasks.count == 1 ? "" : "s")",
                                                   at: now))

                s.addAmbient(AmbientEvent(kind: .info,
                                          text: "\(block.name) started",
                                          at: now,
                                          target: .day))
            }
            cursor += block.minutes
        }

        if changed {
            s.day = plan
            s.saveDay()
        }
    }

    /// First time today that the office network shows up. Clicking the notification opens Day.
    private func announceOfficeArrival(_ office: OfficeNetwork) {
        guard let s = appState else { return }
        let now = Date()
        let planned = s.day.blocks.count

        Notifier.post(title: "You're at \(office.label)",
                      body: planned == 0
                          ? "Nothing blocked out yet — plan the day."
                          : "\(planned) blocks planned. Open Day to fill them in.",
                      id: "office-\(NetworkWatch.dayKey(for: now))",
                      url: "cadence://day")

        s.activityLog.append(ActivityEvent(id: "office-\(NetworkWatch.dayKey(for: now))",
                                           kind: .office,
                                           title: "Arrived at \(office.label)",
                                           detail: planned == 0 ? "No blocks planned yet" : "\(planned) blocks planned",
                                           at: now))

        s.addAmbient(AmbientEvent(kind: .info,
                                  text: "At \(office.label) — plan your day",
                                  at: now,
                                  target: .day))
    }

    private func durationLabel(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h > 0 && r > 0 { return "\(h)h \(r)m" }
        if h > 0 { return "\(h)h" }
        return "\(r)m"
    }
}
