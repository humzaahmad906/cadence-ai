import SwiftUI

struct TopBar: View {
    @EnvironmentObject var appState: AppState
    let route: NavRoute
    var onOpenPalette: () -> Void = {}
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}

    var body: some View {
        HStack(spacing: DS.space4) {
            HStack(spacing: 4) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .disabled(appState.navBack.count < 2)
                    .keyboardShortcut("[", modifiers: [.command])
                    .help("Back")
                Button(action: onForward) { Image(systemName: "chevron.right") }
                    .disabled(appState.navForward.isEmpty)
                    .keyboardShortcut("]", modifiers: [.command])
                    .help("Forward")
            }
            .buttonStyle(TopBarButtonStyle())
            VStack(alignment: .leading, spacing: 2) {
                Text(route.rawValue).font(.system(size: 20, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()

            // Command palette trigger — mimics Docker's search + spotlight combo
            Button(action: onOpenPalette) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("Jump to…").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 40)
                    Text("⌘K").font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(DS.subtleFill))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(width: 260)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DS.subtleFill)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.border, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: { appState.showPasteSprint = true }) {
                    Label("Paste Sprint", systemImage: "doc.on.clipboard")
                }
                Button(action: { Task { await appState.generateDigestDraft() } }) {
                    Label("Digest", systemImage: "text.badge.checkmark")
                }
                Button(action: { Task { await appState.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
            .buttonStyle(TopBarButtonStyle())
        }
        .padding(.horizontal, DS.space6)
        .padding(.vertical, DS.space3)
        .background(DS.contentBG)
        .overlay(Rectangle().fill(DS.border).frame(height: 1), alignment: .bottom)
    }

    private var subtitle: String {
        switch route {
        case .dashboard: return appState.currentSprint.map { "\($0.name) · \($0.daysLeft)d left" } ?? "No active sprint"
        case .kanban:    return "\(appState.tickets.filter { $0.status != .done }.count) open · \(appState.tickets.filter { $0.status == .done }.count) done"
        case .tickets:   return "\(appState.tickets.count) total tickets"
        case .sprints:   return appState.currentSprint.map { "\($0.name) · \($0.daysLeft)d left" } ?? "No active sprint"
        case .projects:  return "Grouped by project key"
        case .digest:    return "Yesterday + today · auto-copy at 2:00 PM"
        case .graph:     return "Explore the knowledge graph"
        case .settings:  return "Preferences and paths"
        }
    }
}

struct TopBarButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hover ? DS.subtleFill : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(DS.border, lineWidth: 1))
            )
            .onHover { hover = $0 }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
