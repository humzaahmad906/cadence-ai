import SwiftUI

struct TicketsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var filter: TicketStatus? = nil
    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                filterPill(nil, label: "All")
                ForEach(TicketStatus.allCases) { s in filterPill(s, label: s.rawValue) }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search title / id / assignee", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(DS.subtleFill))
                .frame(width: 260)
            }
            .padding(DS.space4)

            Divider().overlay(DS.border)

            headerRow

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { t in
                        HoverRow {
                            row(t)
                        }
                        .onTapGesture { appState.selectedTicketId = t.id }
                        Divider().overlay(DS.border)
                    }
                }
            }
        }
        .background(DS.contentBG)
    }

    private var filtered: [Ticket] {
        appState.tickets.filter { t in
            (filter == nil || t.status == filter!) &&
            (query.isEmpty || t.title.localizedCaseInsensitiveContains(query)
                || t.id.localizedCaseInsensitiveContains(query)
                || t.assignee.localizedCaseInsensitiveContains(query))
        }
        .sorted { ($0.priority.rank, $0.status.rawValue) < ($1.priority.rank, $1.status.rawValue) }
    }

    private func filterPill(_ s: TicketStatus?, label: String) -> some View {
        let selected = filter == s
        return Button { filter = s } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DS.accent : Color.primary.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? DS.accentSoft : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var headerRow: some View {
        HStack(spacing: DS.space4) {
            Text("ID").frame(width: 90, alignment: .leading)
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            Text("Status").frame(width: 110, alignment: .leading)
            Text("Priority").frame(width: 70, alignment: .leading)
            Text("Est").frame(width: 40, alignment: .trailing)
            Text("Assignee").frame(width: 120, alignment: .leading)
            Text("Updated").frame(width: 100, alignment: .leading)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.space4)
        .padding(.vertical, DS.space2)
        .background(DS.sidebarBG)
    }

    private func row(_ t: Ticket) -> some View {
        HStack(spacing: DS.space4) {
            Text(t.id).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(t.title).font(.system(size: 13)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                StatusDot(tint: statusTint(t.status))
                Text(t.status.rawValue).font(.system(size: 11))
            }
            .frame(width: 110, alignment: .leading)
            Chip(t.priority.rawValue, tint: priorityTint(t.priority))
                .frame(width: 70, alignment: .leading)
            Text(t.estimate > 0 ? "\(Int(t.estimate))h" : "—")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(t.assignee.isEmpty ? "—" : t.assignee).font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(shortDate(t.updated)).font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
        }
    }

    private func statusTint(_ s: TicketStatus) -> Color {
        switch s {
        case .backlog: return .gray
        case .todo: return DS.accent
        case .inProgress: return DS.warn
        case .inReview: return .purple
        case .done: return DS.ok
        }
    }
    private func priorityTint(_ p: Priority) -> Color {
        switch p {
        case .p0: return DS.danger
        case .p1: return DS.warn
        case .p2: return .yellow
        case .p3: return DS.accent
        case .p4: return .gray
        }
    }
    private func shortDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }
}
