import SwiftUI

struct SprintsView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                if let s = appState.currentSprint {
                    Card {
                        VStack(alignment: .leading, spacing: DS.space3) {
                            HStack {
                                StatusDot(tint: s.daysLeft <= 3 ? DS.danger : DS.ok)
                                Text(s.name).font(.system(size: 16, weight: .bold))
                                Spacer()
                                Text("\(s.daysLeft) days left").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(s.daysLeft <= 3 ? DS.danger : .secondary)
                            }
                            Text("\(s.startDate) → \(s.endDate)").font(.system(size: 12)).foregroundStyle(.secondary)
                            ProgressView(value: progress(s)).tint(DS.accent)
                            HStack(spacing: DS.space4) {
                                stat("Total", appState.tickets.count)
                                stat("Done", appState.tickets.filter { $0.status == .done }.count, tint: DS.ok)
                                stat("In Progress", appState.tickets.filter { $0.status == .inProgress }.count, tint: DS.warn)
                                stat("Blocked", appState.tickets.filter { !$0.blockers.isEmpty }.count, tint: DS.danger)
                                stat("P0/P1 open", appState.tickets.filter { $0.priority.urgent && $0.status != .done }.count, tint: DS.danger)
                            }
                        }
                    }
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No active sprint").font(.system(size: 14, weight: .semibold))
                            Text("Paste sprint tasks with ⇧⌘V or the toolbar button.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(DS.space6)
        }
        .background(DS.contentBG)
    }

    private func progress(_ s: Sprint) -> Double {
        guard let start = s.startDateObj, let end = s.endDateObj, end > start else { return 0 }
        return min(1, max(0, Date().timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    private func stat(_ label: String, _ n: Int, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(n)").font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
