import SwiftUI

/// Library of saved block-based workflows. Create from a template (or blank), edit, run, delete.
struct WorkflowsListView: View {
    @EnvironmentObject var appState: AppState

    // Computed once so ForEach identity in the "New from template" menu stays stable across
    // re-renders (templates() mints fresh UUIDs on every call).
    @State private var templates: [Workflow] = Workflow.templates()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space5) {
                header
                if appState.workflows.isEmpty {
                    empty
                } else {
                    ForEach(appState.workflows) { wf in
                        WorkflowCard(workflow: wf)
                    }
                }
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
        .onAppear { appState.loadWorkflows() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workflows").font(DS.Font.displayL)
                Text("Composable, block-based automations. Chain agent prompts, ticket creation, reviews, and summaries.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            newMenu
        }
    }

    private var newMenu: some View {
        Menu {
            ForEach(templates) { template in
                Button {
                    appState.createWorkflow(from: template)
                } label: {
                    Label(template.name, systemImage: "square.stack.3d.up")
                }
            }
            Divider()
            Button {
                appState.createBlankWorkflow()
            } label: {
                Label("Blank workflow", systemImage: "plus")
            }
        } label: {
            Label("New from template", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).fill(DS.accentGradient))
        .foregroundStyle(.white)
    }

    private var empty: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "flowchart").font(.system(size: 30)).foregroundStyle(DS.textTertiary)
                Text("No workflows yet").font(DS.Font.headline)
                Text("Start from a template — Sprint Kickoff, Daily Digest, or Bug Triage — then tailor the blocks.")
                    .font(DS.Font.body).foregroundStyle(DS.textSecondary)
            }
        }
    }
}

private struct WorkflowCard: View {
    @EnvironmentObject var appState: AppState
    let workflow: Workflow

    @State private var showStartInput = false

    var body: some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workflow.name).font(DS.Font.headline)
                        if !workflow.summary.isEmpty {
                            Text(workflow.summary).font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button { startRun() } label: {
                            Label("Run", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(workflow.blocks.isEmpty || appState.agentRunning)
                        Button { appState.setArtifact(.workflowBuilder(id: workflow.id)) } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }.buttonStyle(SecondaryButtonStyle())
                        Menu {
                            Button(role: .destructive) { appState.deleteWorkflow(workflow.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(DS.textTertiary)
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 20)
                    }
                }
                FlowLayout(spacing: 6) {
                    ForEach(workflow.blocks) { block in
                        HStack(spacing: 4) {
                            Image(systemName: block.kind.icon).font(.caption2)
                            Text(block.title).font(DS.Font.micro)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(DS.subtleFill))
                        .foregroundStyle(DS.textSecondary)
                    }
                    if workflow.blocks.isEmpty {
                        Text("No blocks yet").font(DS.Font.micro).foregroundStyle(DS.textTertiary)
                    }
                }
                HStack(spacing: 12) {
                    Label("\(workflow.blocks.count) block\(workflow.blocks.count == 1 ? "" : "s")", systemImage: "square.stack")
                    Label("\(workflow.repoIds.count) repo\(workflow.repoIds.count == 1 ? "" : "s")", systemImage: "folder")
                }
                .font(DS.Font.micro).foregroundStyle(DS.textTertiary)
            }
        }
        .sheet(isPresented: $showStartInput) {
            WorkflowStartInputSheet(workflowName: workflow.name) { input in
                Task { await appState.runWorkflow(workflow.id, initialInput: input) }
            }
        }
    }

    /// Prompt for a starting input first when the first block consumes it; otherwise run directly.
    private func startRun() {
        if workflow.firstBlockConsumesInput {
            showStartInput = true
        } else {
            Task { await appState.runWorkflow(workflow.id) }
        }
    }
}
