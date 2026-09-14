import SwiftUI

/// The log: one reverse-chronological feed of everything the app did — workflow runs, day
/// blocks starting, arriving at the office. Grouped by day so "what happened yesterday" is a
/// glance rather than a scroll.
struct ActivityView: View {
    @EnvironmentObject var appState: AppState

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", runs = "Runs", day = "Day"
        var id: String { rawValue }
    }

    @State private var filter: Filter = .all
    @State private var events: [ActivityEvent] = []
    /// Rows with nowhere to navigate — an archived day, mostly — open in place instead.
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(DS.borderSoft)

            if visible.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.space5) {
                        ForEach(groups, id: \.0) { day, items in
                            VStack(alignment: .leading, spacing: DS.space2) {
                                Text(day)
                                    .font(DS.Font.callout)
                                    .foregroundStyle(DS.textTertiary)
                                    .padding(.horizontal, DS.space4)

                                Card(padding: DS.space2) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, e in
                                            row(e)
                                            if idx < items.count - 1 {
                                                Divider().overlay(DS.borderSoft).padding(.leading, 44)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(DS.space6)
                }
            }
        }
        .background(DS.contentBG)
        .onAppear(perform: reload)
    }

    // MARK: pieces

    private var toolbar: some View {
        HStack(spacing: DS.space2) {
            ForEach(Filter.allCases) { f in
                Button { filter = f } label: {
                    Text(f.rawValue)
                        .font(DS.Font.callout)
                        .foregroundStyle(filter == f ? DS.accent : DS.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            Capsule().fill(filter == f ? DS.accentSoft : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(visible.count) event\(visible.count == 1 ? "" : "s")")
                .font(DS.Font.caption).foregroundStyle(DS.textTertiary)

            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SecondaryButtonStyle())
                .help("Reload")

            Button { appState.setArtifact(.ticketsList(status: nil)) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Tickets created by workflows")
        }
        .padding(.horizontal, DS.space5)
        .padding(.vertical, DS.space3)
    }

    private func row(_ e: ActivityEvent) -> some View {
        let isOpen = expanded.contains(e.id)
        return Button {
            if let target = e.target {
                appState.setArtifact(target)
            } else if !e.detail.isEmpty {
                if isOpen { expanded.remove(e.id) } else { expanded.insert(e.id) }
            }
        } label: {
            HoverRow {
                HStack(alignment: .top, spacing: DS.space3) {
                    Image(systemName: e.kind.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(tint(e.outcome))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(e.title).font(DS.Font.headline).foregroundStyle(DS.textPrimary)
                            if e.outcome == .failed { Chip("failed", tint: DS.danger) }
                            if e.outcome == .running { Chip("running", tint: DS.warn) }
                        }
                        if !e.detail.isEmpty {
                            Text(e.detail)
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.textSecondary)
                                .lineLimit(isOpen ? nil : 2)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer()

                    Text(Self.time.string(from: e.at))
                        .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
                    if e.target != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10)).foregroundStyle(DS.textTertiary)
                    } else if !e.detail.isEmpty {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(DS.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(e.target == nil && e.detail.isEmpty)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 36)).foregroundStyle(DS.textTertiary)
            Text("Nothing logged yet")
                .font(DS.Font.headline).foregroundStyle(DS.textSecondary)
            Text("Workflow runs and day blocks show up here as they happen.")
                .font(DS.Font.caption).foregroundStyle(DS.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: data

    private func reload() {
        events = appState.activityLog.feed(store: appState.workflowStore)
    }

    private var visible: [ActivityEvent] {
        switch filter {
        case .all:  return events
        case .runs: return events.filter { $0.kind == .workflowRun }
        case .day:  return events.filter { $0.kind != .workflowRun }
        }
    }

    /// Newest day first, events inside each day newest first.
    private var groups: [(String, [ActivityEvent])] {
        let cal = Calendar.current
        var buckets: [Date: [ActivityEvent]] = [:]
        for e in visible {
            buckets[cal.startOfDay(for: e.at), default: []].append(e)
        }
        return buckets.keys.sorted(by: >).map { key in
            (Self.dayLabel(key), buckets[key]!.sorted { $0.at > $1.at })
        }
    }

    private func tint(_ o: ActivityEvent.Outcome) -> Color {
        switch o {
        case .ok:      return DS.ok
        case .failed:  return DS.danger
        case .running: return DS.warn
        case .info:    return DS.accent
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private static func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
        return f.string(from: d)
    }
}
