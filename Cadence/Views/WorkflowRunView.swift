import SwiftUI

/// Live progress for one workflow run: per-block status, captured output, and the
/// approve/edit/reject controls for a paused `manualReview` block.
struct WorkflowRunView: View {
    @EnvironmentObject var appState: AppState
    let runId: String

    @State private var reviewText: String = ""
    /// A persisted-but-inactive run loaded on demand so navigating to it renders read-only
    /// instead of showing "no longer active".
    @State private var fallbackRun: WorkflowRun?

    /// The live active run when it matches this id, otherwise the read-only persisted fallback.
    private var run: WorkflowRun? {
        if let r = appState.activeRun, r.id == runId { return r }
        return fallbackRun
    }

    /// True when we're showing a persisted run rather than the live active one.
    private var isReadOnly: Bool {
        appState.activeRun?.id != runId
    }

    var body: some View {
        Group {
            if let run = run {
                content(run, readOnly: isReadOnly)
            } else {
                notFound
            }
        }
        .onAppear {
            if appState.activeRun?.id != runId, fallbackRun?.id != runId {
                fallbackRun = appState.workflowStore.loadRun(runId)
            }
        }
    }

    private var notFound: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.circle").font(.system(size: 30)).foregroundStyle(DS.textTertiary)
            Text("This run is no longer active").foregroundStyle(DS.textSecondary)
            Button { appState.setArtifact(.workflows) } label: {
                Label("Back to workflows", systemImage: "flowchart")
            }.buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ run: WorkflowRun, readOnly: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space4) {
                header(run)
                ForEach(Array(run.blocks.enumerated()), id: \.element.id) { idx, block in
                    blockCard(run: run, index: idx, block: block, readOnly: readOnly)
                }
            }
            .padding(DS.space6)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(DS.contentBG)
    }

    private func header(_ run: WorkflowRun) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.workflowName).font(DS.Font.displayL)
                HStack(spacing: 8) {
                    statusChip(for: run.status)
                    Text("\(run.blocks.filter { $0.status == .done }.count)/\(run.blocks.count) blocks done")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
            if appState.agentRunning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(appState.agentCurrentTool.map { "Running · \($0)" } ?? "Running…")
                        .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                }
            }
            Button { appState.setArtifact(.workflows) } label: {
                Label("Workflows", systemImage: "flowchart")
            }.buttonStyle(SecondaryButtonStyle())
        }
    }

    @ViewBuilder
    private func blockCard(run: WorkflowRun, index: Int, block: BlockRunState, readOnly: Bool) -> some View {
        Card(padding: DS.space4) {
            VStack(alignment: .leading, spacing: DS.space2) {
                HStack(spacing: DS.space2) {
                    statusIcon(block.status)
                    Text("\(index + 1). \(block.title)").font(DS.Font.headline)
                    Chip(block.kind.label, tint: DS.purple, filled: false)
                    Spacer()
                    Text(block.status.rawValue).font(DS.Font.micro).foregroundStyle(DS.textTertiary)
                }
                if let err = block.error, !err.isEmpty {
                    Text(err).font(DS.Font.caption).foregroundStyle(DS.danger)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if block.status == .awaitingReview && !readOnly {
                    reviewControls(block)
                } else if !block.output.isEmpty {
                    ScrollView {
                        Text(block.output)
                            .font(isProse(block.kind) ? DS.Font.body : DS.Font.mono)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 320)
                    .padding(DS.space2)
                    .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                }
            }
        }
    }

    @ViewBuilder
    private func reviewControls(_ block: BlockRunState) -> some View {
        VStack(alignment: .leading, spacing: DS.space2) {
            let instructions = block.config.reviewInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(instructions.isEmpty ? "Review — edit if needed, then approve to continue." : instructions)
                .font(DS.Font.caption).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $reviewText)
                .font(DS.Font.mono)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 200)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.insetBG))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).stroke(DS.border, lineWidth: 1))
            HStack {
                Button(role: .destructive) {
                    Task { await appState.resumeReview(approve: false, editedOutput: nil) }
                } label: { Label("Reject", systemImage: "xmark") }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    Task { await appState.resumeReview(approve: true, editedOutput: reviewText) }
                } label: { Label("Approve & continue", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .onAppear { reviewText = block.output }
    }

    /// Markdown-ish blocks read better in a proportional font; JSON-shaped output stays monospaced.
    private func isProse(_ kind: WorkflowBlockKind) -> Bool {
        switch kind {
        case .agentPrompt, .createTickets: return false
        case .manualReview, .summarize, .createDescription, .createSolution, .viewer, .docQA, .repoReport: return true
        }
    }

    // MARK: status chrome

    @ViewBuilder
    private func statusIcon(_ status: BlockRunStatus) -> some View {
        switch status {
        case .pending:        Image(systemName: "circle").foregroundStyle(DS.textTertiary)
        case .running:        ProgressView().controlSize(.small)
        case .awaitingReview: Image(systemName: "hand.raised.fill").foregroundStyle(DS.warn)
        case .done:           Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ok)
        case .failed:         Image(systemName: "xmark.octagon.fill").foregroundStyle(DS.danger)
        case .skipped:        Image(systemName: "minus.circle").foregroundStyle(DS.textTertiary)
        }
    }

    private func statusChip(for status: RunStatus) -> some View {
        let tint: Color
        switch status {
        case .pending:        tint = DS.textTertiary
        case .running:        tint = DS.accent
        case .awaitingReview: tint = DS.warn
        case .done:           tint = DS.ok
        case .failed:         tint = DS.danger
        }
        return Chip(status.rawValue, tint: tint)
    }
}
