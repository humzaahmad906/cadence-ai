import SwiftUI
import UniformTypeIdentifiers

struct KanbanView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space3) {
                ForEach(TicketStatus.allCases) { status in
                    KanbanColumn(status: status)
                }
            }
            .padding(DS.space5)
        }
        .background(DS.contentBG)
    }
}

struct KanbanColumn: View {
    @EnvironmentObject var appState: AppState
    let status: TicketStatus
    @State private var hovered = false

    var tickets: [Ticket] {
        appState.tickets
            .filter { $0.status == status }
            .sorted { $0.priority.rank < $1.priority.rank }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space3) {
            HStack(spacing: 8) {
                StatusDot(tint: colTint)
                Text(status.rawValue).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(tickets.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(DS.subtleFill))
            }
            .padding(.horizontal, DS.space3)
            .padding(.top, DS.space3)
            ScrollView {
                LazyVStack(spacing: DS.space2) {
                    ForEach(tickets) { t in
                        TicketCard(ticket: t)
                            .onDrag { NSItemProvider(object: t.id as NSString) }
                            .onTapGesture { appState.selectedTicketId = t.id }
                    }
                    if tickets.isEmpty {
                        Text("Empty").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                }
                .padding(.horizontal, DS.space3)
                .padding(.bottom, DS.space3)
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusL)
                .fill(DS.sidebarBG)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusL)
                        .stroke(hovered ? DS.accent : DS.border, lineWidth: 1)
                )
        )
        .onDrop(of: [.text], isTargeted: $hovered) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let idStr = obj as? String else { return }
                    Task { @MainActor in
                        if let t = appState.tickets.first(where: { $0.id == idStr }) {
                            await appState.moveTicket(t, to: status)
                        }
                    }
                }
            }
            return true
        }
    }

    private var colTint: Color {
        switch status {
        case .backlog: return .gray
        case .todo: return DS.accent
        case .inProgress: return DS.warn
        case .inReview: return .purple
        case .done: return DS.ok
        }
    }
}
