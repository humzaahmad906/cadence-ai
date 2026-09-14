import SwiftUI
import AppKit
import Combine

/// Publishes once a second, but only while something is actually being timed. A menu bar item
/// that redraws every second all day for no reason is a battery cost with nothing to show.
@MainActor
final class SecondTicker: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    func setRunning(_ on: Bool) {
        guard on != (timer != nil) else { return }
        if on {
            now = Date()
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.now = Date() }
            }
            // .common so the count keeps moving while a menu is open or a window is being dragged.
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// What sits in the menu bar: the block being timed and its running total.
struct TimerMenuBarLabel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var ticker: SecondTicker

    var body: some View {
        if let block = appState.day.runningBlock {
            // Rendered as a single string: the menu bar gives a label almost no room, and an
            // HStack of image + text gets clipped before the digits do.
            Text("⏱ \(block.name) · \(DayBlock.clock(block.elapsed(at: ticker.now)))")
        } else {
            Image(systemName: "timer")
        }
    }
}

/// The menu behind it. Deliberately two actions — stop, or go look at the day.
struct TimerMenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject var ticker: SecondTicker

    var body: some View {
        if let block = appState.day.runningBlock {
            Text("\(block.name) — running \(DayBlock.clock(block.elapsed(at: ticker.now)))")
            Divider()
            Button("Pause") { appState.day.stopAllTimers() }
        } else {
            Text("No timer running")
            Divider()
            // Starting from here saves a trip to the window for the common case: you sat down
            // and want the block you were last on running again.
            ForEach(appState.day.blocks) { block in
                Button("Start \(block.name)") { appState.day.toggleTimer(blockId: block.id) }
            }
        }
        Divider()
        Button("Open Day") {
            appState.setArtifact(.day)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }
}
