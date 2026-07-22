import SwiftUI

struct TicketCard: View {
    let ticket: Ticket
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Chip(ticket.priority.rawValue, tint: priorityTint)
                if !ticket.blockers.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text("Blocked").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DS.warn)
                }
                Spacer()
                Text(ticket.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(ticket.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .foregroundStyle(.primary)

            if !ticket.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(ticket.labels.prefix(3), id: \.self) { l in
                        Text(l)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(DS.subtleFill))
                    }
                }
            }

            HStack(spacing: 10) {
                if ticket.estimate > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 9))
                        Text("\(Int(ticket.estimate))h").font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                if !ticket.assignee.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "person.circle.fill").font(.system(size: 10))
                        Text(ticket.assignee).font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(DS.space3)
        .background(
            RoundedRectangle(cornerRadius: DS.radius)
                .fill(DS.cardBG)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radius)
                        .stroke(hover ? DS.accent.opacity(0.5) : (ticket.priority.urgent ? DS.danger.opacity(0.35) : DS.border), lineWidth: 1)
                )
                .shadow(color: hover ? DS.accent.opacity(0.15) : .black.opacity(0.03), radius: hover ? 8 : 2, y: hover ? 4 : 1)
        )
        .onHover { hover = $0 }
    }

    private var priorityTint: Color {
        switch ticket.priority {
        case .p0: return DS.danger
        case .p1: return DS.warn
        case .p2: return .yellow
        case .p3: return DS.accent
        case .p4: return .gray
        }
    }
}

// Kept for callers still using PriorityChip
struct PriorityChip: View {
    let priority: Priority
    var body: some View {
        Chip(priority.rawValue, tint: tint)
    }
    private var tint: Color {
        switch priority {
        case .p0: return DS.danger
        case .p1: return DS.warn
        case .p2: return .yellow
        case .p3: return DS.accent
        case .p4: return .gray
        }
    }
}
