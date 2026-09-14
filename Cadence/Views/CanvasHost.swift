import SwiftUI

/// Central canvas that swaps in the current artifact view.
///
/// Three destinations live in the header — Workflows, Day, Log — and nothing else. Tickets,
/// runs, and builders are reached by clicking through from one of those three.
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

            Button { appState.setArtifact(.workflows) } label: { Label("Workflows", systemImage: "flowchart") }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("1", modifiers: [.command])
                .help("Composable block-based workflows")
            Button { appState.setArtifact(.day) } label: { Label("Day", systemImage: "calendar.day.timeline.left") }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("2", modifiers: [.command])
                .help("Today's blocks")
            Button { appState.setArtifact(.activity) } label: { Label("Log", systemImage: "list.bullet.rectangle.portrait") }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut("3", modifiers: [.command])
                .help("Everything that ran")

            Button { appState.setArtifact(.settings) } label: { Image(systemName: "gearshape") }
                .buttonStyle(SecondaryButtonStyle())
                .help("Settings")
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
        case .workflows:
            WorkflowsListView()
        case .workflowBuilder(let id):
            WorkflowBuilderView(workflowId: id)
        case .workflowRun(let id):
            WorkflowRunView(runId: id)
        case .day:
            DayView()
        case .activity:
            ActivityView()
        case .ticketsList:
            TicketsListView()
        case .ticketDetail(let id):
            if let t = appState.tickets.first(where: { $0.id == id }) {
                TicketDetailView(ticket: t)
            } else {
                emptyState("Ticket \(id) not found.")
            }
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
