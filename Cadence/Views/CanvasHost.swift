import SwiftUI

/// Central canvas that swaps in the current artifact view. Chat drives what appears here.
struct CanvasHost: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.border)
            AmbientStrip()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.contentBG)
    }

    private var header: some View {
        HStack(spacing: DS.space3) {
            HStack(spacing: 4) {
                Button { appState.goBackArtifact() } label: { Image(systemName: "chevron.left") }
                    .disabled(appState.artifactBack.isEmpty)
                    .keyboardShortcut("[", modifiers: [.command])
                    .help("Back")
                Button { appState.goForwardArtifact() } label: { Image(systemName: "chevron.right") }
                    .disabled(appState.artifactForward.isEmpty)
                    .keyboardShortcut("]", modifiers: [.command])
                    .help("Forward")
            }
            .buttonStyle(SecondaryButtonStyle())

            Image(systemName: appState.currentArtifact.icon).foregroundStyle(DS.accent)
            Text(appState.currentArtifact.title).font(DS.Font.title)
            Spacer()

            // Quick jumps — few, chat is the primary router
            Button { appState.setArtifact(.kickoff) } label: { Label("Start", systemImage: "sparkles") }
                .buttonStyle(SecondaryButtonStyle())
                .help("Draft new tickets from a prompt")
            if !appState.tickets.isEmpty {
                Button { appState.setArtifact(.sprintStatus) } label: { Label("Status", systemImage: "flag.checkered") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { appState.setArtifact(.kanban) } label: { Label("Board", systemImage: "rectangle.split.3x1") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if !appState.pendingDrafts.isEmpty {
                Button { appState.setArtifact(.draftStack) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack")
                        Text("Drafts")
                        Text("\(appState.pendingDrafts.count)")
                            .font(DS.Font.micro).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(DS.accent.opacity(0.2))).foregroundStyle(DS.accent)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button { Task { await appState.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SecondaryButtonStyle())
                .help("Refresh")
        }
        .padding(.horizontal, DS.space5)
        .padding(.vertical, DS.space3)
        .background(DS.contentBG)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.currentArtifact {
        case .kickoff:
            KickoffView()
        case .taskSplit:
            TaskSplitView()
        case .wizard:
            WizardView()
        case .sprintStatus:
            SprintStatusView()
        case .kanban:
            KanbanView()
        case .ticketsList:
            TicketsListView()
        case .ticketDetail(let id):
            if let t = appState.tickets.first(where: { $0.id == id }) {
                TicketDetailView(ticket: t)
            } else {
                emptyState("Ticket \(id) not found.")
            }
        case .draftStack:
            DraftReviewStackView()
        case .digest:
            DigestSectionView()
        case .doctrines:
            DoctrinesView()
        case .settings:
            SettingsView()
        case .empty(let reason):
            emptyState(reason)
        }
    }

    private func emptyState(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle").font(.system(size: 40)).foregroundStyle(DS.textTertiary)
            Text(msg).font(DS.Font.headline).foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
